; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Console entry point. M1-01/M1-02 provide WAD access, M1-03 provides PLAYPAL
; and patch decoders, and M1-04 adds an indexed framebuffer plus a windowed
; TITLEPIC presentation mode. Gameplay remains out of scope.
; -----------------------------------------------------------------------------

EnableExplicit

XIncludeFile "Core/Endian.pbi"
XIncludeFile "Core/Fixed.pbi"
XIncludeFile "Core/Angle.pbi"
XIncludeFile "Core/TrigTables.pbi"
XIncludeFile "Renderer/Geometry.pbi"
XIncludeFile "Renderer/Camera.pbi"
XIncludeFile "Renderer/BSP.pbi"
XIncludeFile "Renderer/Projection.pbi"
XIncludeFile "Renderer/ClipSegs.pbi"
XIncludeFile "Renderer/WallVisibility.pbi"
XIncludeFile "Renderer/WallView.pbi"
XIncludeFile "Renderer/WallProject.pbi"
XIncludeFile "Renderer/WallDraw.pbi"
XIncludeFile "Renderer/RenderMain.pbi"
XIncludeFile "WAD/WAD.pbi"
XIncludeFile "Graphics/Palette.pbi"
XIncludeFile "Graphics/Patch.pbi"
XIncludeFile "Graphics/FrameBuffer.pbi"
XIncludeFile "Graphics/Video.pbi"
XIncludeFile "Map/MapLoader.pbi"

#DoomPB_Name    = "DoomPB"
#DoomPB_Version = "0.2.0"

; Exit-code convention shared with scripts/test.ps1 and scripts/test.sh.
#DoomPB_ExitOk      = 0
#DoomPB_ExitFailure = 1
#DoomPB_ExitUsage   = 2

Procedure PrintVersion()
  PrintN(#DoomPB_Name + " " + #DoomPB_Version)
EndProcedure

Procedure PrintHelp()
  PrintN(#DoomPB_Name + " " + #DoomPB_Version + " - native PureBasic source port of Doom")
  PrintN("")
  PrintN("Usage:")
  PrintN("  " + #DoomPB_Name + " [option]")
  PrintN("  " + #DoomPB_Name + " --iwad <path> --dump-info")
  PrintN("  " + #DoomPB_Name + " --iwad <path> --lump-info <name>")
  PrintN("  " + #DoomPB_Name + " --iwad <path> --show-title")
  PrintN("  " + #DoomPB_Name + " --iwad <path> --map-info <ExMy>")
  PrintN("  " + #DoomPB_Name + " --iwad <path> --show-walls <ExMy>")
  PrintN("")
  PrintN("Options:")
  PrintN("  -h, --help       Show this help and exit")
  PrintN("  -v, --version    Show version information and exit")
  PrintN("      --iwad <path>  WAD file to inspect")
  PrintN("      --dump-info    Print WAD header and directory metadata (requires --iwad)")
  PrintN("      --lump-info <name>")
  PrintN("                     Print one lump's index, offset and size (requires --iwad)")
  PrintN("      --show-title   Open a window with TITLEPIC at 3x nearest-neighbour")
  PrintN("                     (requires --iwad; close the window to exit)")
  PrintN("      --map-info <ExMy>")
  PrintN("                     Load and validate a vanilla Doom map (requires --iwad)")
  PrintN("      --show-walls <ExMy>")
  PrintN("                     Render a real M3-05 wall-only 320x200 debug-color frame")
  PrintN("                     from the player-one start at 3x (requires --iwad)")
  PrintN("")
  PrintN("Without options " + #DoomPB_Name + " prints its bootstrap status and exits.")
  PrintN("WAD metadata, named lookup, TITLEPIC presentation and M3-05 wall-only")
  PrintN("debug rendering are available; wall frame pixels are solid debug colors, not")
  PrintN("textured Doom graphics.")
  PrintN("Payload bytes are exposed only through the WAD API, not through this CLI.")
  PrintN("Gameplay is not implemented yet.")
  PrintN("No game data is read unless --iwad is supplied.")
EndProcedure

Procedure PrintBootstrapStatus()
  PrintN(#DoomPB_Name + " " + #DoomPB_Version)
  PrintN("Status: bootstrap build. WAD parsing, lump lookup, PLAYPAL/patch")
  PrintN("decoding, a windowed TITLEPIC mode and an M3-05 wall-only debug frame")
  PrintN("mode are available.")
  PrintN("Gameplay is not implemented yet.")
  PrintN("Use '--iwad <path> --dump-info', '--lump-info <name>', '--show-title',")
  PrintN("'--map-info <ExMy>' or '--show-walls <ExMy>'.")
  PrintN("A legally obtained DOOM.WAD is required for game data, never for this build itself.")
EndProcedure

Procedure PrintUsageError(Message.s)
  PrintN(#DoomPB_Name + ": " + Message)
  PrintN("Try '" + #DoomPB_Name + " --help' for usage.")
EndProcedure

; Prints metadata only: never lump bytes or copyrighted payload data.
Procedure.i DumpWadInfo(Path.s)
  If WADOpen(Path) = #False
    PrintN(#DoomPB_Name + ": " + WADLastError())
    ProcedureReturn #DoomPB_ExitFailure
  EndIf

  PrintN(#DoomPB_Name + " " + #DoomPB_Version)
  PrintN("WAD file: " + WADGetPath())
  PrintN("Type: " + WADGetKindName())
  PrintN("File size: " + Str(WADGetFileSize()))
  PrintN("Lumps: " + Str(WADGetLumpCount()))
  PrintN("Directory offset: " + Str(WADGetDirectoryOffset()))
  PrintN("Directory status: OK")

  WADClose()
  ProcedureReturn #DoomPB_ExitOk
EndProcedure

; Prints lookup metadata only: never lump bytes or copyrighted payload data.
Procedure.i PrintLumpInfo(Path.s, Name.s)
  Protected lumpIndex.i

  If WADOpen(Path) = #False
    PrintN(#DoomPB_Name + ": " + WADLastError())
    ProcedureReturn #DoomPB_ExitFailure
  EndIf

  lumpIndex = WADFindLump(Name)
  If lumpIndex < 0
    PrintN(#DoomPB_Name + ": " + WADLastError())
    WADClose()
    ProcedureReturn #DoomPB_ExitFailure
  EndIf

  PrintN(#DoomPB_Name + " " + #DoomPB_Version)
  PrintN("WAD file: " + WADGetPath())
  PrintN("Lump: " + WADLumpDisplayName(lumpIndex))
  PrintN("Index: " + Str(lumpIndex))
  PrintN("Offset: " + Str(WADLumpPosition(lumpIndex)))
  PrintN("Size: " + Str(WADLumpSize(lumpIndex)))

  WADClose()
  ProcedureReturn #DoomPB_ExitOk
EndProcedure

; Loads PLAYPAL and TITLEPIC, decodes them, composites into the indexed
; framebuffer and presents a 3x nearest-neighbour window. Prints metadata only;
; no payload bytes are emitted.
Procedure.i ShowTitle(Path.s)
  Protected palIndex.i
  Protected titleIndex.i
  Protected palSize.q
  Protected titleSize.q
  Protected palBytes.i = 0
  Protected titleBytes.i = 0
  Protected pal.PaletteSet
  Protected pic.PatchImage
  Protected fb.FrameBuffer
  Protected exitCode.i = #DoomPB_ExitFailure
  Protected errorText.s = ""

  If WADOpen(Path) = #False
    PrintN(#DoomPB_Name + ": " + WADLastError())
    ProcedureReturn #DoomPB_ExitFailure
  EndIf

  palIndex = WADFindLump("PLAYPAL")
  titleIndex = WADFindLump("TITLEPIC")

  If palIndex < 0
    errorText = "PLAYPAL not found: " + WADLastError()
  ElseIf titleIndex < 0
    errorText = "TITLEPIC not found: " + WADLastError()
  Else
    palSize = WADLumpSize(palIndex)
    titleSize = WADLumpSize(titleIndex)
    If palSize <= 0
      errorText = "PLAYPAL is empty."
    ElseIf titleSize <= 0
      errorText = "TITLEPIC is empty."
    Else
      palBytes = AllocateMemory(palSize)
      titleBytes = AllocateMemory(titleSize)
      If palBytes = 0 Or titleBytes = 0
        errorText = "Out of memory while reading TITLEPIC resources."
      ElseIf WADReadLump(palIndex, palBytes, palSize) = #False
        errorText = "Cannot read PLAYPAL: " + WADLastError()
      ElseIf WADReadLump(titleIndex, titleBytes, titleSize) = #False
        errorText = "Cannot read TITLEPIC: " + WADLastError()
      Else
        WADClose()

        If PaletteDecode(palBytes, palSize, @pal) = #False
          errorText = "Cannot decode PLAYPAL: " + PaletteLastError()
        ElseIf PatchDecode(titleBytes, titleSize, @pic) = #False
          errorText = "Cannot decode TITLEPIC: " + PatchLastError()
        Else
          FreeMemory(palBytes)
          palBytes = 0
          FreeMemory(titleBytes)
          titleBytes = 0

          If FrameBufferCreate(@fb, pic\Width, pic\Height) = #False
            errorText = "Cannot create framebuffer: " + FrameBufferLastError()
          ElseIf FrameBufferClear(@fb, 0) = #False
            errorText = "Cannot clear framebuffer: " + FrameBufferLastError()
          ElseIf FrameBufferBlitPatch(@fb, @pic, 0, 0) = #False
            errorText = "Cannot blit TITLEPIC: " + FrameBufferLastError()
          Else
            PrintN(#DoomPB_Name + " " + #DoomPB_Version)
            PrintN("TITLEPIC: " + Str(pic\Width) + "x" + Str(pic\Height) + " -> " + Str(pic\Width * 3) + "x" + Str(pic\Height * 3) + " (3x nearest-neighbour).")
            PrintN("Close the window to exit.")
            If VideoShowFramebuffer(@fb, @pal, 3) = #False
              errorText = "Cannot show TITLEPIC: " + VideoLastError()
            Else
              exitCode = #DoomPB_ExitOk
            EndIf
          EndIf
        EndIf
      EndIf
    EndIf
  EndIf

  If errorText <> ""
    PrintN(#DoomPB_Name + ": " + errorText)
  EndIf

  If palBytes <> 0
    FreeMemory(palBytes)
  EndIf
  If titleBytes <> 0
    FreeMemory(titleBytes)
  EndIf
  FrameBufferReset(@fb)
  PatchReset(@pic)
  PaletteReset(@pal)
  WADClose()
  ProcedureReturn exitCode
EndProcedure

; Loads and validates a map; prints metadata and link counts only.
Procedure.i PrintMapInfo(Path.s, MapName.s)
  Protected level.MapLevel
  Protected canonical.s = MapCanonicalName(MapName)

  If WADOpen(Path) = #False
    PrintN(#DoomPB_Name + ": " + WADLastError())
    ProcedureReturn #DoomPB_ExitFailure
  EndIf

  If MapLevelLoad(MapName, @level) = #False
    PrintN(#DoomPB_Name + ": " + MapLevelLastError())
    MapLevelReset(@level)
    WADClose()
    ProcedureReturn #DoomPB_ExitFailure
  EndIf

  PrintN(#DoomPB_Name + " " + #DoomPB_Version)
  PrintN("WAD file: " + WADGetPath())
  PrintN("Map: " + canonical)
  PrintN("Marker index: " + Str(level\MarkerIndex))
  PrintN("THINGS: " + Str(level\Things\Count))
  PrintN("LINEDEFS: " + Str(level\Linedefs\Count))
  PrintN("SIDEDEFS: " + Str(level\Sidedefs\Count))
  PrintN("VERTEXES: " + Str(level\Vertexes\Count))
  PrintN("SEGS: " + Str(level\Segs\Count))
  PrintN("SSECTORS: " + Str(level\Subsectors\Count))
  PrintN("NODES: " + Str(level\Nodes\Count))
  PrintN("SECTORS: " + Str(level\Sectors\Count))
  PrintN("REJECT: " + Str(level\Reject\Size) + " bytes, required " + Str(level\RejectRequired))
  PrintN("BLOCKMAP: " + Str(level\Blockmap\Width) + "x" + Str(level\Blockmap\Height) + ", cells " + Str(level\BlockmapCells))
  If level\BspRootIsSubsector
    PrintN("BSP root: subsector " + Str(level\BspRootIndex))
  Else
    PrintN("BSP root: node " + Str(level\BspRootIndex))
  EndIf
  PrintN("BSP reachable nodes: " + Str(level\ReachableNodes) + ", unreachable: " + Str(level\UnreachableNodes))
  PrintN("BSP reachable subsectors: " + Str(level\ReachableSubsectors) + ", unreachable: " + Str(level\UnreachableSubsectors))
  PrintN("Validation: OK")

  MapLevelReset(@level)
  WADClose()
  ProcedureReturn #DoomPB_ExitOk
EndProcedure

; Reads one named lump into owned memory from the currently open WAD. Returns a
; null pointer with *OutSize=0 for missing/empty/read failure; never emits bytes.
Procedure.i ShowWallsReadLumpBuffer(Name.s, *OutSize.Quad)
  Protected lumpIndex.i
  Protected lumpSize.q
  Protected memory.i

  *OutSize\q = 0
  lumpIndex = WADFindLump(Name)
  If lumpIndex < 0
    ProcedureReturn 0
  EndIf
  lumpSize = WADLumpSize(lumpIndex)
  If lumpSize <= 0
    ProcedureReturn 0
  EndIf
  memory = AllocateMemory(lumpSize)
  If memory = 0
    ProcedureReturn 0
  EndIf
  If WADReadLump(lumpIndex, memory, lumpSize) = #False
    FreeMemory(memory)
    ProcedureReturn 0
  EndIf
  *OutSize\q = lumpSize
  ProcedureReturn memory
EndProcedure

; Opt-in M3-05 wall-only preview: loads PLAYPAL/PNAMES/TEXTURE1/TEXTURE2,
; builds the F_START/F_END flat catalog, validates one map plus its resources,
; derives the static player-one view (X/Y/heading/viewz), builds the unchanged
; M3-04 ordered visibility spans, renders a real 320x200 debug-color frame
; transactionally and presents it at 3x. Prints metadata/hashes only, never WAD
; bytes, texture/flat pixels, coordinates or screenshots. No fallback camera.
Procedure.i ShowWalls(Path.s, MapName.s)
  Protected canonical.s = MapCanonicalName(MapName)
  Protected wadOpened.i = #False
  Protected palIndex.i
  Protected palSize.q
  Protected pnamesSize.q
  Protected texture1Size.q
  Protected texture2Size.q = 0
  Protected *palBytes.Byte = 0
  Protected *pnamesBytes.Byte = 0
  Protected *texture1Bytes.Byte = 0
  Protected *texture2Bytes.Byte = 0
  Protected hasTexture2.i = #False
  Protected palette.PaletteSet
  Protected pnames.PNamesTable
  Protected textures.TextureCatalog
  Protected flats.FlatCatalog
  Protected level.MapLevel
  Protected projection.Projection
  Protected view.WallView
  Protected visibility.WallVisibilityResult
  Protected target.FrameBuffer
  Protected renderResult.WallRenderResult
  Protected thingIndex.l = 0
  Protected subsectorIndex.l = 0
  Protected sectorIndex.l = 0
  Protected spanCount.l = 0
  Protected segmentCount.l = 0
  Protected processedColumns.l = 0
  Protected drawnPixels.l = 0
  Protected middlePixels.l = 0
  Protected upperPixels.l = 0
  Protected lowerPixels.l = 0
  Protected drawRanges.l = 0
  Protected emptyColumns.l = 0
  Protected clippedColumns.l = 0
  Protected hash.q = 0
  Protected flatCount.l = 0
  Protected textureCount.l = 0
  Protected pnamesCount.l = 0
  Protected paletteCount.l = 0
  Protected windowTitle.s = ""
  Protected errorText.s = ""
  Protected exitCode.i = #DoomPB_ExitFailure

  If WADOpen(Path) = #False
    PrintN(#DoomPB_Name + ": " + WADLastError())
    ProcedureReturn #DoomPB_ExitFailure
  EndIf
  wadOpened = #True

  palIndex = WADFindLump("PLAYPAL")
  If palIndex < 0
    errorText = "PLAYPAL not found: " + WADLastError()
  Else
    palSize = WADLumpSize(palIndex)
    If palSize <= 0
      errorText = "PLAYPAL is empty."
    Else
      *palBytes = AllocateMemory(palSize)
      If *palBytes = 0
        errorText = "Out of memory reading PLAYPAL."
      ElseIf WADReadLump(palIndex, *palBytes, palSize) = #False
        errorText = "Cannot read PLAYPAL: " + WADLastError()
      ElseIf PaletteDecode(*palBytes, palSize, @palette) = #False
        errorText = "Cannot decode PLAYPAL: " + PaletteLastError()
      EndIf
      If *palBytes <> 0
        FreeMemory(*palBytes)
        *palBytes = 0
      EndIf
      If errorText = ""
        paletteCount = PaletteCount(@palette)
      EndIf
    EndIf
  EndIf

  If errorText = ""
    *pnamesBytes = ShowWallsReadLumpBuffer("PNAMES", @pnamesSize)
    If *pnamesBytes = 0
      errorText = "PNAMES is missing, empty or unreadable."
    ElseIf PNamesDecode(*pnamesBytes, pnamesSize, @pnames) = #False
      errorText = "Cannot decode PNAMES: " + PNamesLastError()
    EndIf
    If *pnamesBytes <> 0
      FreeMemory(*pnamesBytes)
      *pnamesBytes = 0
    EndIf
    If errorText = ""
      pnamesCount = PNamesCount(@pnames)
      If pnamesCount <= 0
        errorText = "PNAMES has no patch names."
      EndIf
    EndIf
  EndIf

  If errorText = ""
    *texture1Bytes = ShowWallsReadLumpBuffer("TEXTURE1", @texture1Size)
    If *texture1Bytes = 0
      errorText = "TEXTURE1 is missing, empty or unreadable."
    Else
      hasTexture2 = Bool(WADFindLump("TEXTURE2") >= 0)
      If hasTexture2
        *texture2Bytes = ShowWallsReadLumpBuffer("TEXTURE2", @texture2Size)
        If *texture2Bytes = 0
          errorText = "TEXTURE2 exists but is empty or unreadable."
        EndIf
      EndIf
    EndIf
  EndIf
  If errorText = ""
    If TextureCatalogDecode(*texture1Bytes, texture1Size, *texture2Bytes,
                            texture2Size, hasTexture2, @textures) = #False
      errorText = "Cannot decode TEXTURE1/TEXTURE2: " + TextureDefsLastError()
    EndIf
  EndIf
  If *texture1Bytes <> 0
    FreeMemory(*texture1Bytes)
    *texture1Bytes = 0
  EndIf
  If *texture2Bytes <> 0
    FreeMemory(*texture2Bytes)
    *texture2Bytes = 0
  EndIf

  If errorText = ""
    If TextureCatalogResolve(@textures, @pnames) = #False
      errorText = "Cannot resolve texture patch names against the WAD: " + TextureDefsLastError()
    Else
      textureCount = TextureCatalogCount(@textures)
      If textureCount <= 0
        errorText = "TEXTURE1/TEXTURE2 define no textures."
      EndIf
    EndIf
  EndIf

  If errorText = ""
    If FlatCatalogBuild(@flats) = #False
      errorText = "Cannot build the F_START/F_END flat catalog: " + FlatLastError()
    Else
      flatCount = FlatCatalogCount(@flats)
      If flatCount <= 0
        errorText = "F_START/F_END flat namespace is empty."
      EndIf
    EndIf
  EndIf

  If errorText = ""
    If MapLevelLoad(canonical, @level) = #False
      errorText = "Cannot load map " + canonical + ": " + MapLevelLastError()
    EndIf
  EndIf
  If errorText = ""
    If MapLevelValidateResources(@level, @flats, @textures) = #False
      errorText = "Map resource binding failed: " + MapLevelLastError()
    EndIf
  EndIf
  If errorText = ""
    If ProjectionInitClassic(@projection) = #False
      errorText = "Cannot initialize the classic 320-column projection: " + ProjectionLastError()
    EndIf
  EndIf
  If errorText = ""
    If WallRenderPlayerStartView(@level, @view, @thingIndex, @subsectorIndex,
                                 @sectorIndex) = #False
      errorText = "Cannot derive the player-one start view: " + WallRenderLastError()
    EndIf
  EndIf
  If errorText = ""
    If WallVisibilityBuild(@level, @view\Camera, @projection, @flats,
                           @textures, @visibility) = #False
      errorText = "Cannot build wall visibility: " + WallVisibilityLastError()
    ElseIf WallVisibilityCount(@visibility) <= 0
      errorText = "Wall visibility produced zero visible spans for " + canonical + "."
    Else
      spanCount = WallVisibilityCount(@visibility)
    EndIf
  EndIf
  If errorText = ""
    If WallRenderFrame(@level, @view, @projection, @flats, @textures,
                       @visibility, @target, @renderResult, #True) = #False
      errorText = "Cannot render wall-only frame: " + WallRenderLastError()
    ElseIf WallRenderGetStats(@renderResult, @spanCount, @segmentCount,
                             0, @processedColumns, @drawnPixels, @middlePixels,
                             @upperPixels, @lowerPixels, 0, 0, 0, @drawRanges,
                             @emptyColumns, @clippedColumns, 0, 0, @hash, 0) = #False
      errorText = "Cannot read rendered wall statistics: " + WallRenderLastError()
    ElseIf drawnPixels <= 0
      errorText = "Rendered wall frame contains zero wall pixels."
    EndIf
  EndIf

  If errorText = ""
    WADClose()
    wadOpened = #False
  EndIf

  If errorText = ""
    PrintN(#DoomPB_Name + " " + #DoomPB_Version)
    PrintN("Map: " + canonical)
    PrintN("PLAYPAL colors: " + Str(paletteCount))
    PrintN("PNAMES names: " + Str(pnamesCount) + ", textures: " + Str(textureCount) +
           ", flats: " + Str(flatCount))
    PrintN("Player-one THING index: " + Str(thingIndex) +
           ", subsector: " + Str(subsectorIndex) + ", floor sector: " + Str(sectorIndex))
    PrintN("View height source: player start floor + VIEWHEIGHT 41 units (static, no bob).")
    PrintN("Visible wall spans: " + Str(spanCount) + ", draw metadata records: " + Str(segmentCount))
    PrintN("Columns processed: " + Str(processedColumns) + ", draw ranges: " + Str(drawRanges))
    PrintN("Wall pixels: middle " + Str(middlePixels) + ", upper " + Str(upperPixels) +
           ", lower " + Str(lowerPixels) + ", total " + Str(drawnPixels))
    PrintN("Vertical clipping: clipped columns " + Str(clippedColumns) +
           ", empty columns " + Str(emptyColumns))
    PrintN("Debug palette indices: background " + Str(#WALLDRAW_BackgroundIndex) +
           ", middle " + Str(#WALLDRAW_MiddleIndex) + ", upper " + Str(#WALLDRAW_UpperIndex) +
           ", lower " + Str(#WALLDRAW_LowerIndex) + " (not textured).")
    PrintN("Frame: 320x200 row-major indexed plane, at " + Str(#VIDEO_DefaultScale) +
           "x nearest-neighbour presentation.")
    PrintN("Frame hash (FNV-1a64, 64000 palette bytes): " + WallFrameHashHex64(hash))
    PrintN("Close the window to exit.")
    windowTitle = "DoomPB - M3-05 wall-only debug colors (" + canonical + ")"
    If VideoShowFramebuffer(@target, @palette, #VIDEO_DefaultScale, windowTitle) = #False
      errorText = "Cannot show the wall-only frame: " + VideoLastError()
    Else
      exitCode = #DoomPB_ExitOk
    EndIf
  EndIf

  If errorText <> ""
    PrintN(#DoomPB_Name + ": " + errorText)
  EndIf

  ; All owned buffers/objects are released on every path; no WAD bytes retained.
  FrameBufferReset(@target)
  WallRenderResultReset(@renderResult)
  WallVisibilityReset(@visibility)
  WallViewReset(@view)
  ProjectionReset(@projection)
  MapLevelReset(@level)
  FlatCatalogReset(@flats)
  TextureCatalogReset(@textures)
  PNamesReset(@pnames)
  PaletteReset(@palette)
  If wadOpened
    WADClose()
  EndIf
  ProcedureReturn exitCode
EndProcedure

Define argumentCount.i
Define argument.s
Define exitCode.i = #DoomPB_ExitOk
Define wadPath.s = ""
Define dumpInfo.i = #False
Define lumpInfo.i = #False
Define lumpName.s = ""
Define showTitle.i = #False
Define mapInfo.i = #False
Define mapName.s = ""
Define showWalls.i = #False
Define wallsMapName.s = ""
Define sawIwad.i = #False
Define index.i
Define parseError.s = ""

; PrintN() needs an attached console in this build; harmless when stdout is redirected.
OpenConsole()

argumentCount = CountProgramParameters()

If argumentCount = 0
  PrintBootstrapStatus()
ElseIf argumentCount = 1
  argument = ProgramParameter(0)
  Select LCase(argument)
    Case "-h", "--help", "-?"
      PrintHelp()
    Case "-v", "--version"
      PrintVersion()
    Case "--iwad"
      PrintUsageError("'--iwad' requires a file path.")
      exitCode = #DoomPB_ExitUsage
    Case "--dump-info"
      PrintUsageError("'--dump-info' requires '--iwad <path>'.")
      exitCode = #DoomPB_ExitUsage
    Case "--lump-info"
      PrintUsageError("'--lump-info' requires '--iwad <path> <name>'.")
      exitCode = #DoomPB_ExitUsage
    Case "--show-title"
      PrintUsageError("'--show-title' requires '--iwad <path>'.")
      exitCode = #DoomPB_ExitUsage
    Case "--map-info"
      PrintUsageError("'--map-info' requires '--iwad <path> <ExMy>'.")
      exitCode = #DoomPB_ExitUsage
    Case "--show-walls"
      PrintUsageError("'--show-walls' requires '--iwad <path> <ExMy>'.")
      exitCode = #DoomPB_ExitUsage
    Default
      PrintUsageError("unknown option '" + argument + "'.")
      exitCode = #DoomPB_ExitUsage
  EndSelect
Else
  index = 0
  While index < argumentCount And parseError = ""
    argument = ProgramParameter(index)
    Select LCase(argument)
      Case "--iwad"
        If sawIwad
          parseError = "duplicate '--iwad' option."
        ElseIf index + 1 >= argumentCount
          parseError = "'--iwad' requires a file path."
        Else
          index + 1
          wadPath = ProgramParameter(index)
          If wadPath = ""
            parseError = "'--iwad' requires a non-empty file path."
          Else
            sawIwad = #True
          EndIf
        EndIf
      Case "--dump-info"
        If dumpInfo
          parseError = "duplicate '--dump-info' option."
        Else
          dumpInfo = #True
        EndIf
      Case "--lump-info"
        If lumpInfo
          parseError = "duplicate '--lump-info' option."
        ElseIf index + 1 >= argumentCount
          parseError = "'--lump-info' requires a lump name."
        Else
          index + 1
          lumpName = ProgramParameter(index)
          If lumpName = ""
            parseError = "'--lump-info' requires a non-empty lump name."
          Else
            lumpInfo = #True
          EndIf
        EndIf
      Case "--show-title"
        If showTitle
          parseError = "duplicate '--show-title' option."
        Else
          showTitle = #True
        EndIf
      Case "--map-info"
        If mapInfo
          parseError = "duplicate '--map-info' option."
        ElseIf index + 1 >= argumentCount
          parseError = "'--map-info' requires a map name."
        Else
          index + 1
          mapName = ProgramParameter(index)
          If mapName = ""
            parseError = "'--map-info' requires a non-empty map name."
          Else
            mapInfo = #True
          EndIf
        EndIf
      Case "--show-walls"
        If showWalls
          parseError = "duplicate '--show-walls' option."
        ElseIf index + 1 >= argumentCount
          parseError = "'--show-walls' requires a map name."
        Else
          index + 1
          wallsMapName = ProgramParameter(index)
          If wallsMapName = ""
            parseError = "'--show-walls' requires a non-empty map name."
          Else
            showWalls = #True
          EndIf
        EndIf
      Default
        parseError = "unknown option '" + argument + "'."
    EndSelect
    index + 1
  Wend

  If parseError <> ""
    PrintUsageError(parseError)
    exitCode = #DoomPB_ExitUsage
  ElseIf dumpInfo + lumpInfo + showTitle + mapInfo + showWalls > 1
    PrintUsageError("only one of '--dump-info', '--lump-info', '--show-title', '--map-info' and '--show-walls' may be used.")
    exitCode = #DoomPB_ExitUsage
  ElseIf dumpInfo And sawIwad
    exitCode = DumpWadInfo(wadPath)
  ElseIf lumpInfo And sawIwad
    exitCode = PrintLumpInfo(wadPath, lumpName)
  ElseIf showTitle And sawIwad
    exitCode = ShowTitle(wadPath)
  ElseIf mapInfo And sawIwad
    exitCode = PrintMapInfo(wadPath, mapName)
  ElseIf showWalls And sawIwad
    exitCode = ShowWalls(wadPath, wallsMapName)
  ElseIf dumpInfo
    PrintUsageError("'--dump-info' requires '--iwad <path>'.")
    exitCode = #DoomPB_ExitUsage
  ElseIf lumpInfo
    PrintUsageError("'--lump-info' requires '--iwad <path> <name>'.")
    exitCode = #DoomPB_ExitUsage
  ElseIf showTitle
    PrintUsageError("'--show-title' requires '--iwad <path>'.")
    exitCode = #DoomPB_ExitUsage
  ElseIf mapInfo
    PrintUsageError("'--map-info' requires '--iwad <path> <ExMy>'.")
    exitCode = #DoomPB_ExitUsage
  ElseIf showWalls
    PrintUsageError("'--show-walls' requires '--iwad <path> <ExMy>'.")
    exitCode = #DoomPB_ExitUsage
  ElseIf sawIwad
    PrintUsageError("'--iwad' requires '--dump-info', '--lump-info <name>', '--show-title', '--map-info <ExMy>' or '--show-walls <ExMy>'.")
    exitCode = #DoomPB_ExitUsage
  Else
    PrintUsageError("no action specified.")
    exitCode = #DoomPB_ExitUsage
  EndIf
EndIf

End exitCode
