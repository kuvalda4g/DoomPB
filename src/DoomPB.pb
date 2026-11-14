; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; M0 bootstrap entry point. This file deliberately contains no WAD parsing and
; no game engine code; both start with milestone M1.
; -----------------------------------------------------------------------------

EnableExplicit

#DoomPB_Name    = "DoomPB"
#DoomPB_Version = "0.0.1"

; Exit-code convention shared with scripts/test.ps1 and scripts/test.sh.
#DoomPB_ExitOk    = 0
#DoomPB_ExitUsage = 2

Procedure PrintVersion()
  PrintN(#DoomPB_Name + " " + #DoomPB_Version)
EndProcedure

Procedure PrintHelp()
  PrintN(#DoomPB_Name + " " + #DoomPB_Version + " - native PureBasic source port of Doom")
  PrintN("")
  PrintN("Usage: " + #DoomPB_Name + " [option]")
  PrintN("")
  PrintN("Options:")
  PrintN("  -h, --help      Show this help and exit")
  PrintN("  -v, --version   Show version information and exit")
  PrintN("")
  PrintN("Without options " + #DoomPB_Name + " prints its bootstrap status and exits.")
  PrintN("The WAD loader and the game engine are not implemented yet (milestone M0).")
  PrintN("No game data is read or required by this build.")
EndProcedure

Procedure PrintBootstrapStatus()
  PrintN(#DoomPB_Name + " " + #DoomPB_Version)
  PrintN("Status: bootstrap build. The WAD loader and the game engine are not implemented yet.")
  PrintN("No game data is required by this build; a legally obtained DOOM.WAD will be")
  PrintN("needed from milestone M1 onwards.")
EndProcedure

Procedure PrintUsageError(Message.s)
  PrintN(#DoomPB_Name + ": " + Message)
  PrintN("Try '" + #DoomPB_Name + " --help' for usage.")
EndProcedure

Define argumentCount.i
Define argument.s
Define exitCode.i = #DoomPB_ExitOk

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
    Default
      PrintUsageError("unknown option '" + argument + "'.")
      exitCode = #DoomPB_ExitUsage
  EndSelect
Else
  PrintUsageError("too many arguments; expected at most one option.")
  exitCode = #DoomPB_ExitUsage
EndIf

End exitCode
