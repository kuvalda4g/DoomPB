; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Flat namespace catalog and 64x64 indexed flat decoder.
;
; R_InitFlats() in the original uses firstflat = W_GetNumForName("F_START") + 1
; and lastflat = W_GetNumForName("F_END") - 1. DoomPB uses WADFindLump(), which
; returns the last matching marker in the single open WAD. Markers are excluded
; from the catalog; the interior range preserves physical directory order.
;
; A vanilla flat is exactly 64*64 = 4096 palette-index bytes with no header,
; transparency or RGB conversion. Index 255 is a valid opaque color.
;
; Name lookup here is namespace-constrained and uses the last matching flat in
; the discovered range. Vanilla R_FlatNumForName first does a global WAD lookup
; (last match) and subtracts firstflat; the two differ only in unusual
; cross-namespace name collisions.
;
; Ownership:
;   - FlatCatalog/FlatImage are caller-owned, zero-initialized once.
;   - Catalogs own copies of names, WAD indices and sizes.
;   - FlatImage owns a private 4096-byte copy; it survives source-buffer release.
;   - Reset frees memory, is idempotent and a failed build/decode leaves the
;     affected object empty.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_FLAT_PBI, #PB_Constant) = 0

#DOOMPB_FLAT_PBI = 1

XIncludeFile "../WAD/WAD.pbi"

#FLAT_Width             = 64
#FLAT_Height            = 64
#FLAT_ByteSize          = 4096
#FLAT_MaxCount          = 65536

#FLAT_CatalogMagic      = $464C5431
#FLAT_ImageMagic        = $464C4931

Structure FlatCatalog
  Magic.l
  Count.l
  FirstLump.l
  LastLump.l
  *Names.Byte
  *WadIndices.Long
  *Sizes.Long
EndStructure

Structure FlatImage
  Magic.l
  Width.l
  Height.l
  PixelCount.q
  *Pixels.Byte
EndStructure

Global gFlat_LastError.s = ""

Procedure FlatSetError(Message.s)
  gFlat_LastError = Message
EndProcedure

Procedure.s FlatLastError()
  ProcedureReturn gFlat_LastError
EndProcedure

Procedure.i FlatCatalogReset(*Catalog.FlatCatalog)
  If *Catalog = 0
    FlatSetError("Flat catalog pointer is null.")
    ProcedureReturn #False
  EndIf

  If *Catalog\Magic = #FLAT_CatalogMagic
    If *Catalog\Names <> 0
      FreeMemory(*Catalog\Names)
    EndIf
    If *Catalog\WadIndices <> 0
      FreeMemory(*Catalog\WadIndices)
    EndIf
    If *Catalog\Sizes <> 0
      FreeMemory(*Catalog\Sizes)
    EndIf
  EndIf

  *Catalog\Magic = 0
  *Catalog\Count = 0
  *Catalog\FirstLump = 0
  *Catalog\LastLump = 0
  *Catalog\Names = 0
  *Catalog\WadIndices = 0
  *Catalog\Sizes = 0
  gFlat_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i FlatImageReset(*Image.FlatImage)
  If *Image = 0
    FlatSetError("Flat image pointer is null.")
    ProcedureReturn #False
  EndIf

  If *Image\Magic = #FLAT_ImageMagic
    If *Image\Pixels <> 0
      FreeMemory(*Image\Pixels)
    EndIf
  EndIf

  *Image\Magic = 0
  *Image\Width = 0
  *Image\Height = 0
  *Image\PixelCount = 0
  *Image\Pixels = 0
  gFlat_LastError = ""
  ProcedureReturn #True
EndProcedure

; Discovers F_START/F_END in the currently open WAD. An empty interior range
; (end == start + 1) is valid and yields count 0.
Procedure.i FlatCatalogBuild(*Catalog.FlatCatalog)
  Protected startIndex.i
  Protected endIndex.i
  Protected count.q
  Protected names.i = 0
  Protected indices.i = 0
  Protected sizes.i = 0
  Protected i.i
  Protected byteIndex.i
  Protected absoluteIndex.i

  If *Catalog = 0
    FlatSetError("Flat catalog pointer is null.")
    ProcedureReturn #False
  EndIf
  FlatCatalogReset(*Catalog)

  If WADIsOpen() = #False
    FlatSetError("No WAD is open.")
    ProcedureReturn #False
  EndIf

  startIndex = WADFindLump("F_START")
  endIndex = WADFindLump("F_END")
  If startIndex < 0
    FlatSetError("F_START marker is missing.")
    ProcedureReturn #False
  EndIf
  If endIndex < 0
    FlatSetError("F_END marker is missing.")
    ProcedureReturn #False
  EndIf
  If startIndex >= endIndex
    FlatSetError("Flat namespace markers are reversed: F_START=" + Str(startIndex) + ", F_END=" + Str(endIndex) + ".")
    ProcedureReturn #False
  EndIf

  count = Int(endIndex) - Int(startIndex) - 1
  If count > #FLAT_MaxCount
    FlatSetError("Flat namespace is too large: " + Str(count) + " entries.")
    ProcedureReturn #False
  EndIf

  If count > 0
    names = AllocateMemory(count * 8)
    indices = AllocateMemory(count * 4)
    sizes = AllocateMemory(count * 4)
    If names = 0 Or indices = 0 Or sizes = 0
      If names <> 0
        FreeMemory(names)
      EndIf
      If indices <> 0
        FreeMemory(indices)
      EndIf
      If sizes <> 0
        FreeMemory(sizes)
      EndIf
      FlatSetError("Out of memory while building the flat catalog.")
      ProcedureReturn #False
    EndIf
    For i = 0 To count - 1
      absoluteIndex = startIndex + 1 + i
      For byteIndex = 0 To 7
        PokeA(names + i * 8 + byteIndex, WADLumpRawNameByte(absoluteIndex, byteIndex))
      Next
      PokeL(indices + i * 4, absoluteIndex)
      PokeL(sizes + i * 4, WADLumpSize(absoluteIndex))
    Next
  EndIf

  *Catalog\Magic = #FLAT_CatalogMagic
  *Catalog\Count = count
  *Catalog\FirstLump = startIndex + 1
  *Catalog\LastLump = endIndex - 1
  *Catalog\Names = names
  *Catalog\WadIndices = indices
  *Catalog\Sizes = sizes
  gFlat_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i FlatCatalogCount(*Catalog.FlatCatalog)
  If *Catalog = 0 Or *Catalog\Magic <> #FLAT_CatalogMagic
    FlatSetError("Flat catalog is not initialized.")
    ProcedureReturn 0
  EndIf
  ProcedureReturn *Catalog\Count
EndProcedure

Procedure.i FlatCatalogGetEntry(*Catalog.FlatCatalog, RelativeIndex.i, *WadIndex.Long, *LumpSize.Long)
  If *Catalog = 0 Or *Catalog\Magic <> #FLAT_CatalogMagic
    FlatSetError("Flat catalog is not initialized.")
    ProcedureReturn #False
  EndIf
  If RelativeIndex < 0 Or RelativeIndex >= *Catalog\Count
    FlatSetError("Flat catalog index out of range: " + Str(RelativeIndex) + " (count " + Str(*Catalog\Count) + ").")
    ProcedureReturn #False
  EndIf
  If *WadIndex <> 0
    PokeL(*WadIndex, PeekL(*Catalog\WadIndices + RelativeIndex * 4))
  EndIf
  If *LumpSize <> 0
    PokeL(*LumpSize, PeekL(*Catalog\Sizes + RelativeIndex * 4))
  EndIf
  gFlat_LastError = ""
  ProcedureReturn #True
EndProcedure

Procedure.i FlatCatalogNameByte(*Catalog.FlatCatalog, RelativeIndex.i, ByteOffset.i)
  If *Catalog = 0 Or *Catalog\Magic <> #FLAT_CatalogMagic
    FlatSetError("Flat catalog is not initialized.")
    ProcedureReturn -1
  EndIf
  If RelativeIndex < 0 Or RelativeIndex >= *Catalog\Count
    FlatSetError("Flat catalog index out of range: " + Str(RelativeIndex) + ".")
    ProcedureReturn -1
  EndIf
  If ByteOffset < 0 Or ByteOffset >= 8
    FlatSetError("Flat name byte offset out of range: " + Str(ByteOffset) + ".")
    ProcedureReturn -1
  EndIf
  ProcedureReturn PeekA(*Catalog\Names + RelativeIndex * 8 + ByteOffset)
EndProcedure

Procedure.s FlatCatalogDisplayName(*Catalog.FlatCatalog, RelativeIndex.i)
  Protected i.i
  Protected value.i
  Protected result.s = ""

  If *Catalog = 0 Or *Catalog\Magic <> #FLAT_CatalogMagic
    FlatSetError("Flat catalog is not initialized.")
    ProcedureReturn ""
  EndIf
  If RelativeIndex < 0 Or RelativeIndex >= *Catalog\Count
    FlatSetError("Flat catalog index out of range: " + Str(RelativeIndex) + ".")
    ProcedureReturn ""
  EndIf
  For i = 0 To 7
    value = PeekA(*Catalog\Names + RelativeIndex * 8 + i)
    If value = 0
      Break
    EndIf
    If value >= 32 And value <= 126
      result + Chr(value)
    Else
      result + "."
    EndIf
  Next
  gFlat_LastError = ""
  ProcedureReturn result
EndProcedure

; Namespace-constrained, case-insensitive-by-query flat lookup. The last
; matching entry within the range wins; stored bytes are not modified.
Procedure.i FlatCatalogFindName(*Catalog.FlatCatalog, Name.s)
  Protected Dim query.a(7)
  Protected nameLength.i
  Protected i.i
  Protected value.i
  Protected entry.i
  Protected matched.i
  Protected stored.i

  If *Catalog = 0 Or *Catalog\Magic <> #FLAT_CatalogMagic
    FlatSetError("Flat catalog is not initialized.")
    ProcedureReturn -1
  EndIf
  If Name = ""
    FlatSetError("Flat name is empty.")
    ProcedureReturn -1
  EndIf

  nameLength = Len(Name)
  If nameLength > 8
    nameLength = 8
  EndIf
  For i = 0 To Len(Name) - 1
    value = Asc(Mid(Name, i + 1, 1))
    If value < 32 Or value > 126
      FlatSetError("Flat query contains an unsupported character.")
      ProcedureReturn -1
    EndIf
    If value >= 97 And value <= 122
      value = value - 32
    EndIf
    If i < 8
      query(i) = value
    EndIf
  Next
  For i = nameLength To 7
    query(i) = 0
  Next

  For entry = *Catalog\Count - 1 To 0 Step -1
    matched = #True
    For i = 0 To 7
      stored = PeekA(*Catalog\Names + entry * 8 + i)
      If stored <> query(i)
        matched = #False
        Break
      EndIf
    Next
    If matched
      gFlat_LastError = ""
      ProcedureReturn entry
    EndIf
  Next

  FlatSetError("Flat not found: " + Name)
  ProcedureReturn -1
EndProcedure

; Decodes exactly 4096 bytes into an owned 64x64 index plane.
Procedure.i FlatDecode(*Bytes.Byte, Length.q, *Image.FlatImage)
  Protected pixels.i

  If *Image = 0
    FlatSetError("Flat image pointer is null.")
    ProcedureReturn #False
  EndIf
  FlatImageReset(*Image)

  If Length <> #FLAT_ByteSize
    FlatSetError("Flat payload must be exactly 4096 bytes; got " + Str(Length) + ".")
    ProcedureReturn #False
  EndIf
  If *Bytes = 0
    FlatSetError("Flat payload pointer is null.")
    ProcedureReturn #False
  EndIf

  pixels = AllocateMemory(#FLAT_ByteSize)
  If pixels = 0
    FlatSetError("Out of memory while decoding a flat.")
    ProcedureReturn #False
  EndIf
  CopyMemory(*Bytes, pixels, #FLAT_ByteSize)

  *Image\Magic = #FLAT_ImageMagic
  *Image\Width = #FLAT_Width
  *Image\Height = #FLAT_Height
  *Image\PixelCount = #FLAT_ByteSize
  *Image\Pixels = pixels
  gFlat_LastError = ""
  ProcedureReturn #True
EndProcedure

; Reads and decodes a flat by relative catalog index.
Procedure.i FlatLoad(*Catalog.FlatCatalog, RelativeIndex.i, *Image.FlatImage)
  Protected wadIndex.l
  Protected lumpSize.l
  Protected bytes.i
  Protected result.i

  If *Catalog = 0 Or *Catalog\Magic <> #FLAT_CatalogMagic
    FlatSetError("Flat catalog is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Image = 0
    FlatSetError("Flat image pointer is null.")
    ProcedureReturn #False
  EndIf
  FlatImageReset(*Image)
  If RelativeIndex < 0 Or RelativeIndex >= *Catalog\Count
    FlatSetError("Flat catalog index out of range: " + Str(RelativeIndex) + ".")
    ProcedureReturn #False
  EndIf
  If WADIsOpen() = #False
    FlatSetError("No WAD is open.")
    ProcedureReturn #False
  EndIf

  wadIndex = PeekL(*Catalog\WadIndices + RelativeIndex * 4)
  lumpSize = PeekL(*Catalog\Sizes + RelativeIndex * 4)
  If lumpSize <> #FLAT_ByteSize
    FlatSetError("Flat lump has the wrong size: " + Str(lumpSize) + " (expected 4096).")
    ProcedureReturn #False
  EndIf

  bytes = AllocateMemory(lumpSize)
  If bytes = 0
    FlatSetError("Out of memory while reading a flat.")
    ProcedureReturn #False
  EndIf
  If WADReadLump(wadIndex, bytes, lumpSize) = #False
    FlatSetError("Cannot read flat lump: " + WADLastError())
    FreeMemory(bytes)
    ProcedureReturn #False
  EndIf
  result = FlatDecode(bytes, lumpSize, *Image)
  FreeMemory(bytes)
  ProcedureReturn result
EndProcedure

Procedure.i FlatImageGetPixel(*Image.FlatImage, X.i, Y.i)
  If *Image = 0 Or *Image\Magic <> #FLAT_ImageMagic
    FlatSetError("Flat image is not initialized.")
    ProcedureReturn -1
  EndIf
  If X < 0 Or Y < 0 Or X >= #FLAT_Width Or Y >= #FLAT_Height
    FlatSetError("Flat coordinate out of range: " + Str(X) + "," + Str(Y) + ".")
    ProcedureReturn -1
  EndIf
  ProcedureReturn PeekA(*Image\Pixels + Int(Y) * #FLAT_Width + Int(X))
EndProcedure

CompilerEndIf
