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

; ReadData() is documented with a 2 GB per-call limit. Payload sizes are
; int32 (below 2 GB), but reads are still split into bounded chunks so the
; behaviour stays explicit and portable.
#WAD_ReadChunkSize       = 16 * 1024 * 1024

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
; Named lookup (M1-02)
;
; Reproduces W_CheckNumForName from w_wad.c without a cache:
;   - the query is ASCII-uppercased (a-z only, no locale/Unicode folding);
;   - exactly eight name bytes are compared (NUL-padded when shorter);
;   - queries longer than eight bytes use their first eight bytes;
;   - the directory is scanned backwards, so the last duplicate wins.
; Stored directory name bytes are never modified. A directory that stores a
; lowercase name therefore does not match an uppercased query, which matches
; the original raw-byte comparison.
; ---------------------------------------------------------------------------

; Fills QueryBytes[0..7] with the normalized, NUL-padded query and validates
; every query character. Returns #False (and sets the error) for an empty or
; non-printable-ASCII name.
Procedure.i WADPrepareQuery(Name.s, *QueryBytes.Byte)
  Protected nameLength.i = Len(Name)
  Protected i.i
  Protected value.i

  If nameLength = 0
    WADSetError("Lump name is empty.")
    ProcedureReturn #False
  EndIf

  ; Validate the entire query. Only the first eight bytes take part in the
  ; comparison, but accepting non-ASCII trailing characters silently would
  ; make the truncation rule surprising.
  For i = 0 To nameLength - 1
    value = Asc(Mid(Name, i + 1, 1))
    If value < 32 Or value > 126
      WADSetError("Lump name contains an unsupported character (printable ASCII only).")
      ProcedureReturn #False
    EndIf
    If value >= 97 And value <= 122
      value = value - 32
    EndIf
    If i < #WAD_LumpNameSize
      PokeA(*QueryBytes + i, value)
    EndIf
  Next

  ; strncpy() semantics: a short query is NUL-padded to eight bytes.
  If nameLength < #WAD_LumpNameSize
    For i = nameLength To #WAD_LumpNameSize - 1
      PokeA(*QueryBytes + i, 0)
    Next
  EndIf

  ProcedureReturn #True
EndProcedure

; Returns the zero-based directory index of the winning entry, or -1 when no
; entry matches or no WAD is open. Lookup never reads payload data and never
; modifies the directory. WADLastError() distinguishes "not found", invalid
; query text and "no WAD is open"; a successful lookup clears it.
Procedure.i WADFindLump(Name.s)
  Protected Dim query.a(7)   ; exactly #WAD_LumpNameSize bytes
  Protected entry.i
  Protected byteIndex.i
  Protected storedByte.i
  Protected matched.i

  If gWAD_IsOpen = #False
    WADSetError("No WAD is open.")
    ProcedureReturn -1
  EndIf

  If WADPrepareQuery(Name, @query(0)) = #False
    ProcedureReturn -1
  EndIf

  If gWAD_LumpCount > 0
    For entry = gWAD_LumpCount - 1 To 0 Step -1
      matched = #True
      For byteIndex = 0 To #WAD_LumpNameSize - 1
        storedByte = gWAD_Lumps(entry)\NameBytes[byteIndex]
        If storedByte <> query(byteIndex)
          matched = #False
          Break
        EndIf
      Next
      If matched
        gWAD_LastError = ""
        ProcedureReturn entry
      EndIf
    Next
  EndIf

  WADSetError("Lump not found: " + Name)
  ProcedureReturn -1
EndProcedure

; ---------------------------------------------------------------------------
; Payload reading (M1-02)
;
; Reads one validated directory entry into a caller-owned buffer:
;   WADReadLump(Index, *Destination, Capacity) -> #True / #False
;
; The caller allocates and frees *Destination and guarantees that Capacity
; bytes are writable. The function never allocates a replacement buffer and
; never converts bytes to a string. Capacity may exceed the lump size; only
; WADLumpSize(Index) bytes are written.
;
; Because WADOpen() closes its file handle, each nonempty read reopens the WAD
; read-only by its saved path, verifies that the current length still matches
; the parsed snapshot, rechecks position + size in 64-bit arithmetic, reads in
; bounded chunks and closes the temporary handle on every path.
;
; Zero-length entries (markers) succeed immediately with zero bytes read and
; accept a null destination. Their raw recorded position is never used.
;
; Basic validation (index, capacity, destination, file presence, file length,
; range, seek position) happens before the first payload byte is written. A
; short read can still leave the destination partially modified; that case is
; reported as an error. An equal-size replacement of the file cannot be
; detected by these checks.
; ---------------------------------------------------------------------------
Procedure.i WADReadLump(Index.i, *Destination, Capacity.q)
  Protected position.l
  Protected lumpSize.l
  Protected file.i = 0
  Protected currentSize.q
  Protected entryEnd.q
  Protected written.q = 0
  Protected chunk.q

  If gWAD_IsOpen = #False
    WADSetError("No WAD is open.")
    ProcedureReturn #False
  EndIf

  If Index < 0 Or Index >= gWAD_LumpCount
    WADSetError("Lump index out of range: " + Str(Index) + " (count " + Str(gWAD_LumpCount) + ").")
    ProcedureReturn #False
  EndIf

  If Capacity < 0
    WADSetError("Read capacity is negative.")
    ProcedureReturn #False
  EndIf

  position = gWAD_Lumps(Index)\Position
  lumpSize = gWAD_Lumps(Index)\Size

  ; Markers have no payload: success without touching the file or destination.
  If lumpSize = 0
    gWAD_LastError = ""
    ProcedureReturn #True
  EndIf

  If *Destination = 0
    WADSetError("Destination buffer is null for a nonempty lump.")
    ProcedureReturn #False
  EndIf

  If Capacity < lumpSize
    WADSetError("Destination capacity is too small: " + Str(Capacity) + " < " + Str(lumpSize) + ".")
    ProcedureReturn #False
  EndIf

  ; WADOpen() already rejected negative positions for nonempty entries; this is
  ; a defensive recheck of the invariant before it is used in arithmetic.
  If position < 0
    WADSetError("Lump position is negative.")
    ProcedureReturn #False
  EndIf

  file = ReadFile(#PB_Any, gWAD_Path)
  If file = 0
    WADSetError("Cannot reopen WAD file: " + gWAD_Path)
    ProcedureReturn #False
  EndIf

  currentSize = Lof(file)
  If currentSize <> gWAD_FileSize
    CloseFile(file)
    WADSetError("WAD file size changed since it was opened (expected " + Str(gWAD_FileSize) + ", now " + Str(currentSize) + ").")
    ProcedureReturn #False
  EndIf

  ; Int() widens to the native 64-bit integer before the addition, so a large
  ; signed 32-bit position cannot wrap.
  entryEnd = Int(position) + Int(lumpSize)
  If entryEnd > currentSize
    CloseFile(file)
    WADSetError("Lump data is outside the current WAD file (ends at byte " + Str(entryEnd) + ", file size " + Str(currentSize) + ").")
    ProcedureReturn #False
  EndIf

  FileSeek(file, position)
  If Loc(file) <> position
    CloseFile(file)
    WADSetError("Cannot seek to lump data at byte " + Str(position) + ".")
    ProcedureReturn #False
  EndIf

  While written < lumpSize
    chunk = lumpSize - written
    If chunk > #WAD_ReadChunkSize
      chunk = #WAD_ReadChunkSize
    EndIf
    If ReadData(file, *Destination + written, chunk) <> chunk
      CloseFile(file)
      WADSetError("Short read while loading lump " + Str(Index) + " at byte offset " + Str(written) + ".")
      ProcedureReturn #False
    EndIf
    written + chunk
  Wend

  CloseFile(file)
  gWAD_LastError = ""
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
