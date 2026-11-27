; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Shared M3-04/M3-05 canonical WAD slot-name and flat/texture identity readers.
;
; Extracted from WallVisibility.pbi unchanged so the online plane hook and
; WallProject can reuse the exact catalog-aware/raw-byte fallback semantics
; without WallProject including WallVisibility (would be an include cycle).
;
; Status policy:
;   WallFlatSlotStatus/WallWallSlotStatus: 0 canonical name, 1 canonical unused
;   "-"/all-NUL slot, 2 noncanonical bytes, 3 decoder/API read failure.
;   WallSectorFlatIdentity: catalog-aware resolved index equality for canonical
;   names; without a catalog the narrowly defined canonical raw-byte comparison
;   is used (noncanonical sectors are conservatively not identical). A genuine
;   flat catalog index 0 is an ordinary flat.
;   WallMiddleTextureAbsent: catalog-aware reproduces original
;   texturetranslation[midtexture]==0 including the genuine first texture index
;   zero quirk; without a catalog canonical "-"/all-NUL is absent and malformed
;   wall slots are conservatively present.
;
; Errors are explicit in gWallIdentity_LastError; callers wrap the deepest text
; in their own diagnostic. Read failures never invent an identity or index and
; are never confused with a conservative fallback verdict.
;
; No allocation, pointer retention, pixel access or WAD I/O occurs here.
;
; Original algorithms copyright (C) 1993-1996 by id Software, Inc.
; Port implementation copyright (C) 2026 DoomPB contributors.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_WALLIDENTITY_PBI, #PB_Constant) = 0

#DOOMPB_WALLIDENTITY_PBI = 1

XIncludeFile "../Core/Fixed.pbi"
XIncludeFile "../Map/MapLevel.pbi"
XIncludeFile "../Graphics/Flat.pbi"
XIncludeFile "../Graphics/TextureDefs.pbi"

Structure WallSlotNameOut
  Value.s
EndStructure

Global gWallIdentity_LastError.s = ""

Procedure WallIdentitySetError(Message.s)
  gWallIdentity_LastError = Message
EndProcedure

Procedure.s WallIdentityLastError()
  ProcedureReturn gWallIdentity_LastError
EndProcedure

Procedure.i WallFlatSlotStatus(*Level.MapLevel, SectorIndex.l, Field.l, *Out.WallSlotNameOut)
  Protected byteIndex.i
  Protected value.i
  Protected sawNul.i = 0
  Protected result.s = ""

  sawNul = #False
  For byteIndex = 0 To 7
    value = MapSectorsNameByte(@*Level\Sectors, SectorIndex, Field, byteIndex)
    If value < 0
      WallIdentitySetError("Wall flat slot read failed at " + *Level\Name + " sector " + Str(SectorIndex) + " field " + Str(Field) + ".")
      ProcedureReturn 3
    EndIf
    If sawNul
      If value <> 0 And value <> 32
        ProcedureReturn 2
      EndIf
    ElseIf value = 0
      sawNul = #True
    ElseIf value < 32 Or value > 126
      ProcedureReturn 2
    Else
      result + Chr(value)
    EndIf
  Next
  If Len(result) = 0
    ProcedureReturn 2
  EndIf
  *Out\Value = result
  ProcedureReturn 0
EndProcedure

Procedure.i WallWallSlotStatus(*Level.MapLevel, SideIndex.l, Field.l, *Out.WallSlotNameOut)
  Protected byteIndex.i
  Protected value.i
  Protected sawNul.i = 0
  Protected result.s = ""

  value = MapSidedefsNameByte(@*Level\Sidedefs, SideIndex, Field, 0)
  If value < 0
    WallIdentitySetError("Wall wall slot read failed at " + *Level\Name + " sidedef " + Str(SideIndex) + " field " + Str(Field) + ".")
    ProcedureReturn 3
  EndIf
  If value = 0 Or value = Asc("-")
    For byteIndex = 1 To 7
      value = MapSidedefsNameByte(@*Level\Sidedefs, SideIndex, Field, byteIndex)
      If value < 0
        WallIdentitySetError("Wall wall slot read failed at " + *Level\Name + " sidedef " + Str(SideIndex) + " field " + Str(Field) + ".")
        ProcedureReturn 3
      EndIf
      If value <> 0 And value <> 32
        ProcedureReturn 2
      EndIf
    Next
    *Out\Value = ""
    ProcedureReturn 1
  EndIf

  sawNul = #False
  For byteIndex = 0 To 7
    value = MapSidedefsNameByte(@*Level\Sidedefs, SideIndex, Field, byteIndex)
    If value < 0
      WallIdentitySetError("Wall wall slot read failed at " + *Level\Name + " sidedef " + Str(SideIndex) + " field " + Str(Field) + ".")
      ProcedureReturn 3
    EndIf
    If sawNul
      If value <> 0 And value <> 32
        ProcedureReturn 2
      EndIf
    ElseIf value = 0
      sawNul = #True
    ElseIf value < 32 Or value > 126
      ProcedureReturn 2
    Else
      result + Chr(value)
    EndIf
  Next
  If Len(result) = 0
    ProcedureReturn 2
  EndIf
  *Out\Value = result
  ProcedureReturn 0
EndProcedure

Procedure.i WallSectorFlatIdentity(*Level.MapLevel, *Flats.FlatCatalog,
                                   SectorA.l, SectorB.l, Field.l, *Same.Long)
  Protected statusA.i
  Protected statusB.i
  Protected nameA.WallSlotNameOut
  Protected nameB.WallSlotNameOut
  Protected indexA.i
  Protected indexB.i
  Protected byteIndex.i
  Protected byteA.i
  Protected byteB.i

  If *Flats <> 0
    statusA = WallFlatSlotStatus(*Level, SectorA, Field, @nameA)
    If statusA = 3
      ProcedureReturn #False
    EndIf
    If statusA <> 0
      WallIdentitySetError("Wall flats: " + *Level\Name + " sector " + Str(SectorA) +
                           " has a noncanonical floor/ceiling flat slot.")
      ProcedureReturn #False
    EndIf
    statusB = WallFlatSlotStatus(*Level, SectorB, Field, @nameB)
    If statusB = 3
      ProcedureReturn #False
    EndIf
    If statusB <> 0
      WallIdentitySetError("Wall flats: " + *Level\Name + " sector " + Str(SectorB) +
                           " has a noncanonical floor/ceiling flat slot.")
      ProcedureReturn #False
    EndIf
    indexA = FlatCatalogFindName(*Flats, nameA\Value)
    If indexA < 0
      WallIdentitySetError("Wall flats: " + *Level\Name + " sector " + Str(SectorA) +
                           " flat not found in the catalog: " + nameA\Value)
      ProcedureReturn #False
    EndIf
    indexB = FlatCatalogFindName(*Flats, nameB\Value)
    If indexB < 0
      WallIdentitySetError("Wall flats: " + *Level\Name + " sector " + Str(SectorB) +
                           " flat not found in the catalog: " + nameB\Value)
      ProcedureReturn #False
    EndIf
    *Same\l = Bool(indexA = indexB)
    ProcedureReturn #True
  EndIf

  statusA = WallFlatSlotStatus(*Level, SectorA, Field, @nameA)
  If statusA = 3
    ProcedureReturn #False
  EndIf
  statusB = WallFlatSlotStatus(*Level, SectorB, Field, @nameB)
  If statusB = 3
    ProcedureReturn #False
  EndIf
  If statusA <> 0 Or statusB <> 0
    *Same\l = 0
    ProcedureReturn #True
  EndIf
  For byteIndex = 0 To 7
    byteA = MapSectorsNameByte(@*Level\Sectors, SectorA, Field, byteIndex)
    byteB = MapSectorsNameByte(@*Level\Sectors, SectorB, Field, byteIndex)
    If byteA < 0 Or byteB < 0
      WallIdentitySetError("Wall flats: raw eight-byte comparison read failed.")
      ProcedureReturn #False
    EndIf
    If byteA <> byteB
      *Same\l = 0
      ProcedureReturn #True
    EndIf
  Next
  *Same\l = 1
  ProcedureReturn #True
EndProcedure

Procedure.i WallMiddleTextureAbsent(*Level.MapLevel, *Textures.TextureCatalog,
                                    SideIndex.l, *Absent.Long)
  Protected status.i
  Protected nameSlot.WallSlotNameOut
  Protected resolvedIndex.i

  If *Textures <> 0
    status = WallWallSlotStatus(*Level, SideIndex, 2, @nameSlot)
    If status = 3
      ProcedureReturn #False
    EndIf
    If status = 2
      WallIdentitySetError("Wall textures: " + *Level\Name + " sidedef " + Str(SideIndex) +
                           " middle slot is noncanonical.")
      ProcedureReturn #False
    EndIf
    If status = 1
      *Absent\l = 1
      ProcedureReturn #True
    EndIf
    resolvedIndex = TextureCatalogFindName(*Textures, nameSlot\Value)
    If resolvedIndex < 0
      WallIdentitySetError("Wall textures: " + *Level\Name + " sidedef " + Str(SideIndex) +
                           " middle texture not found in the catalog: " + nameSlot\Value)
      ProcedureReturn #False
    EndIf
    *Absent\l = Bool(resolvedIndex = 0)
    ProcedureReturn #True
  EndIf

  status = WallWallSlotStatus(*Level, SideIndex, 2, @nameSlot)
  If status = 3
    ProcedureReturn #False
  EndIf
  If status = 1
    *Absent\l = 1
    ProcedureReturn #True
  EndIf
  *Absent\l = 0
  ProcedureReturn #True
EndProcedure

CompilerEndIf
