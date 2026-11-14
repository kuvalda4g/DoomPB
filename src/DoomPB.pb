; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Console entry point. M1-01 provides WAD header/directory metadata and M1-02
; provides named lookup plus payload reads through the WAD API; graphics and
; gameplay belong to later tasks.
; -----------------------------------------------------------------------------

EnableExplicit

XIncludeFile "Core/Endian.pbi"
XIncludeFile "WAD/WAD.pbi"

#DoomPB_Name    = "DoomPB"
#DoomPB_Version = "0.0.1"

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
  PrintN("")
  PrintN("Options:")
  PrintN("  -h, --help       Show this help and exit")
  PrintN("  -v, --version    Show version information and exit")
  PrintN("      --iwad <path>  WAD file to inspect")
  PrintN("      --dump-info    Print WAD header and directory metadata (requires --iwad)")
  PrintN("      --lump-info <name>")
  PrintN("                     Print one lump's index, offset and size (requires --iwad)")
  PrintN("")
  PrintN("Without options " + #DoomPB_Name + " prints its bootstrap status and exits.")
  PrintN("WAD metadata and named lookup are available so far (milestone M1-02).")
  PrintN("Payload bytes are exposed only through the WAD API, not through this CLI.")
  PrintN("Graphics and gameplay are not implemented yet.")
  PrintN("No game data is read unless --iwad is supplied.")
EndProcedure

Procedure PrintBootstrapStatus()
  PrintN(#DoomPB_Name + " " + #DoomPB_Version)
  PrintN("Status: bootstrap build. WAD header/directory parsing and named lump")
  PrintN("lookup are available; payload reading exists in the WAD API only.")
  PrintN("Graphics and gameplay are not implemented yet.")
  PrintN("Use '" + #DoomPB_Name + " --iwad <path> --dump-info' or '--lump-info <name>' to inspect a WAD.")
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

Define argumentCount.i
Define argument.s
Define exitCode.i = #DoomPB_ExitOk
Define wadPath.s = ""
Define dumpInfo.i = #False
Define lumpInfo.i = #False
Define lumpName.s = ""
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
      Default
        parseError = "unknown option '" + argument + "'."
    EndSelect
    index + 1
  Wend

  If parseError <> ""
    PrintUsageError(parseError)
    exitCode = #DoomPB_ExitUsage
  ElseIf dumpInfo And lumpInfo
    PrintUsageError("'--dump-info' and '--lump-info' cannot be combined.")
    exitCode = #DoomPB_ExitUsage
  ElseIf dumpInfo And sawIwad
    exitCode = DumpWadInfo(wadPath)
  ElseIf lumpInfo And sawIwad
    exitCode = PrintLumpInfo(wadPath, lumpName)
  ElseIf dumpInfo
    PrintUsageError("'--dump-info' requires '--iwad <path>'.")
    exitCode = #DoomPB_ExitUsage
  ElseIf lumpInfo
    PrintUsageError("'--lump-info' requires '--iwad <path> <name>'.")
    exitCode = #DoomPB_ExitUsage
  ElseIf sawIwad
    PrintUsageError("'--iwad' requires '--dump-info' or '--lump-info <name>'.")
    exitCode = #DoomPB_ExitUsage
  Else
    PrintUsageError("no action specified.")
    exitCode = #DoomPB_ExitUsage
  EndIf
EndIf

End exitCode
