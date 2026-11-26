; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; M3-06 vanilla 320-column static wall lighting. Builds the original
; R_ExecuteSetViewSize `scalelight[LIGHTLEVELS][MAXLIGHTSCALE]` map-level table
; for the canonical high-detail viewport from the decoded COLORMAP, selects the
; front-sector light row with original horizontal/vertical line corrections,
; derives the column scale index from rw_scale and maps a composed texture texel
; through `colormap[lightTable][texel]`.
;
; Constants are the pinned r_main.h values:
;   LIGHTLEVELS=16, LIGHTSEGSHIFT=4, MAXLIGHTSCALE=48, LIGHTSCALESHIFT=12,
;   NUMCOLORMAPS=32, DISTMAP=2.
; Table generation preserves the source formulas:
;   startmap = ((LIGHTLEVELS-1-i)*2)*NUMCOLORMAPS/LIGHTLEVELS;  [= (15-i)*4]
;   level = startmap - j*SCREENWIDTH/(viewwidth<<detailshift)/DISTMAP;
;   canonical viewwidth=320, detailshift=0 -> step = j*320/320/2 = j/2
;   truncation; level clamped 0..31.
; Light row selection preserves:
;   lightnum=(frontsector->lightlevel >> LIGHTSEGSHIFT)+extralight;
;   v1->y==v2->y -> lightnum--; else v1->x==v2->x -> lightnum++;
;   clamp 0..15.
; Column selection: index=rw_scale>>LIGHTSCALESHIFT; if >=48 -> 47.
;
; Static-MVP limits:
;   - COLORMAP must expose at least 32 complete tables; more tables are accepted
;     but only 0..31 are referenced by classic wall lighting;
;   - extralight is fixed at 0. Sector dynamic light flashes and fixedcolormap are
;     deferred, so a nonzero Extralight argument is rejected instead of silently
;     inventing a flash state;
;   - light table stores numeric COLORMAP map indexes, not borrowed table
;     pointers, so the table remains independent of the ColormapSet lifetime;
;     each lookup revalidates the live COLORMAP object and 0..31 map index before
;     direct PeekA, preserving table identity and bounds.
;
; Ownership: caller zero-initializes WallScalelightTable. Build owns a single
; 768-Long (16*48) allocation and replaces previous data transactionally; Reset
; frees it idempotently and leaves an empty reusable object. No RGB conversion,
; gamma, bilinear interpolation, palette mutation or per-column rebuild exists.
;
; Original algorithms copyright (C) 1993-1996 by id Software, Inc.
; Port implementation copyright (C) 2026 DoomPB contributors.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_WALLLIGHTING_PBI, #PB_Constant) = 0

#DOOMPB_WALLLIGHTING_PBI = 1

XIncludeFile "../Core/Fixed.pbi"
XIncludeFile "../Graphics/Colormap.pbi"
XIncludeFile "Projection.pbi"

#LIGHT_Magic = $4C494231
#LIGHT_LEVELS = 16
#LIGHT_SEGSHIFT = 4
#LIGHT_MAXLIGHTSCALE = 48
#LIGHT_SCALESHIFT = 12
#LIGHT_NUMCOLORMAPS = 32
#LIGHT_DISTMAP = 2
#LIGHT_SCREENWIDTH = #PROJ_VIEWWIDTH
#LIGHT_DETAILSHIFT = 0
#LIGHT_BinCount = #LIGHT_LEVELS * #LIGHT_MAXLIGHTSCALE
#LIGHT_MapCountMin = #LIGHT_NUMCOLORMAPS
#LIGHT_MaxMapIndex = #LIGHT_NUMCOLORMAPS - 1
#LIGHT_NoBin = -1

Structure WallScalelightTable
  Magic.l
  Ready.l
  Count.l
  Capacity.l
  *MapIndex.Long
  Allocations.l
EndStructure

Global gWallLighting_LastError.s = ""

Procedure WallLightingSetError(Message.s)
  gWallLighting_LastError = Message
EndProcedure

Procedure.s WallLightingLastError()
  ProcedureReturn gWallLighting_LastError
EndProcedure

Procedure.i WallScalelightTableIsValid(*Table.WallScalelightTable)
  ProcedureReturn Bool(*Table <> 0 And *Table\Magic = #LIGHT_Magic And *Table\Ready <> 0)
EndProcedure

Procedure.i WallScalelightTableReset(*Table.WallScalelightTable)
  If *Table = 0
    WallLightingSetError("Wall scalelight table pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Table\Magic = #LIGHT_Magic
    If *Table\MapIndex <> 0
      If *Table\Capacity <> #LIGHT_BinCount Or *Table\Count < 0 Or *Table\Count > *Table\Capacity
        WallLightingSetError("Wall scalelight table owned pointer/capacity metadata is inconsistent.")
        ProcedureReturn #False
      EndIf
      FreeMemory(*Table\MapIndex)
    EndIf
  ElseIf *Table\Magic <> 0
    WallLightingSetError("Wall scalelight table has an unrecognized Magic value.")
    ProcedureReturn #False
  ElseIf *Table\MapIndex <> 0
    WallLightingSetError("Wall scalelight table has an unexplained map-index pointer without a Magic value.")
    ProcedureReturn #False
  EndIf

  FillMemory(*Table, Int(SizeOf(WallScalelightTable)), 0)
  *Table\Magic = #LIGHT_Magic
  gWallLighting_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; COLORMAP availability gate
; ---------------------------------------------------------------------------

; Classic wall lighting needs at least 32 complete 256-byte tables. The decoder
; already rejects non-multiple lengths; this is the renderer-level gate.
Procedure.i WallLightingValidateColormap(*Colormap.ColormapSet, *MapCount.Long)
  If *Colormap = 0 Or *Colormap\Magic <> #COLORMAP_Magic
    WallLightingSetError("Wall lighting: COLORMAP is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Colormap\MapCount <= 0 Or *Colormap\MapCount > #COLORMAP_MaxTables
    WallLightingSetError("Wall lighting: COLORMAP map count is outside the decoder domain.")
    ProcedureReturn #False
  EndIf
  If *Colormap\Tables = 0
    WallLightingSetError("Wall lighting: COLORMAP table pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Colormap\MapCount < #LIGHT_MapCountMin
    WallLightingSetError("Wall lighting requires at least " + Str(#LIGHT_MapCountMin) +
                         " COLORMAP tables; the lump has " + Str(*Colormap\MapCount) + ".")
    ProcedureReturn #False
  EndIf
  If *MapCount <> 0
    PokeL(*MapCount, *Colormap\MapCount)
  EndIf
  gWallLighting_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; R_ExecuteSetViewSize scalelight[16][48] table generation
; ---------------------------------------------------------------------------

; Reproduces the canonical viewport formula with signed32 Long arithmetic and
; original integer truncation, storing clamped COLORMAP map level 0..31.
Procedure.i WallScalelightTableBuild(*Table.WallScalelightTable,
                                     *Colormap.ColormapSet)
  Protected binBytes.q
  Protected mapCount.l = 0
  Protected levelIndex.l
  Protected scaleIndex.l
  Protected startMap.l
  Protected stepNumerator.l
  Protected stepDenominator.l
  Protected stepValue.l
  Protected level.l
  Protected binIndex.i
  Protected allocations.l = 0

  WallLightingSetError("")
  If *Table = 0
    WallLightingSetError("WallScalelightTableBuild: table pointer is null.")
    ProcedureReturn #False
  EndIf
  If *Table\Magic <> 0 And *Table\Magic <> #LIGHT_Magic
    WallLightingSetError("WallScalelightTableBuild: table has an unrecognized Magic value.")
    ProcedureReturn #False
  EndIf
  If WallScalelightTableReset(*Table) = #False
    ProcedureReturn #False
  EndIf
  If WallLightingValidateColormap(*Colormap, @mapCount) = #False
    ProcedureReturn #False
  EndIf

  binBytes = Int(#LIGHT_BinCount) * SizeOf(Long)
  If binBytes <= 0 Or binBytes <> Int(#LIGHT_BinCount) * Int(SizeOf(Long))
    WallLightingSetError("Wall scalelight bin byte arithmetic is invalid.")
    ProcedureReturn #False
  EndIf
  *Table\MapIndex = AllocateMemory(binBytes)
  If *Table\MapIndex = 0
    WallLightingSetError("Out of memory for the wall scalelight map-index table.")
    ProcedureReturn #False
  EndIf
  FillMemory(*Table\MapIndex, Int(binBytes), 0)
  allocations + 1

  For levelIndex = 0 To #LIGHT_LEVELS - 1
    startMap = ((#LIGHT_LEVELS - 1 - levelIndex) * 2) * #LIGHT_NUMCOLORMAPS / #LIGHT_LEVELS
    If startMap < 0 Or startMap > (#LIGHT_LEVELS - 1) * 2 * #LIGHT_NUMCOLORMAPS / #LIGHT_LEVELS
      WallLightingSetError("Wall scalelight startmap is outside the source domain 0..60 for level " + Str(levelIndex) + ": " + Str(startMap) + ".")
      FreeMemory(*Table\MapIndex)
      *Table\MapIndex = 0
      ProcedureReturn #False
    EndIf
    For scaleIndex = 0 To #LIGHT_MAXLIGHTSCALE - 1
      ; j*SCREENWIDTH/(viewwidth<<detailshift): both multiply/divide by the same
      ; canonical width yields j; subsequent DISTMAP division truncates j/2.
      stepNumerator = scaleIndex * #LIGHT_SCREENWIDTH
      stepDenominator = #PROJ_VIEWWIDTH << #LIGHT_DETAILSHIFT
      If stepDenominator <= 0
        WallLightingSetError("Wall scalelight denominator is nonpositive.")
        FreeMemory(*Table\MapIndex)
        *Table\MapIndex = 0
        ProcedureReturn #False
      EndIf
      stepValue = stepNumerator / stepDenominator / #LIGHT_DISTMAP
      If stepValue < 0 Or stepValue > scaleIndex + 1
        WallLightingSetError("Wall scalelight step arithmetic produced an invalid truncation: " + Str(stepValue) + ".")
        FreeMemory(*Table\MapIndex)
        *Table\MapIndex = 0
        ProcedureReturn #False
      EndIf
      level = startMap - stepValue
      If level < 0
        level = 0
      EndIf
      If level >= #LIGHT_NUMCOLORMAPS
        level = #LIGHT_MAXMapIndex
      EndIf
      If level < 0 Or level > #LIGHT_MAXMapIndex
        WallLightingSetError("Wall scalelight level clamp failed.")
        FreeMemory(*Table\MapIndex)
        *Table\MapIndex = 0
        ProcedureReturn #False
      EndIf
      binIndex = levelIndex * #LIGHT_MAXLIGHTSCALE + scaleIndex
      PokeL(*Table\MapIndex + binIndex * SizeOf(Long), level)
    Next
  Next

  *Table\Magic = #LIGHT_Magic
  *Table\Ready = 1
  *Table\Count = #LIGHT_BinCount
  *Table\Capacity = #LIGHT_BinCount
  *Table\Allocations = allocations
  gWallLighting_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; light row selection and column scale index
; ---------------------------------------------------------------------------

; Original sector-light row correction. FrontLight is the raw nonnegative sector
; lightlevel; vertex raw map coordinates select horizontal (same Y), vertical
; (same X) or diagonal (neither). extralight is static 0.
Procedure.i WallLightingLightNumChecked(FrontLight.l, V1Y.l, V2Y.l, V1X.l, V2X.l,
                                        ExtraLight.l, *LightNum.Long)
  Protected shifted.l

  WallLightingSetError("")
  If *LightNum = 0
    WallLightingSetError("WallLightingLightNumChecked: output pointer is null.")
    ProcedureReturn #False
  EndIf
  If FrontLight < 0
    WallLightingSetError("Wall lighting: front sector lightlevel is negative: " + Str(FrontLight) + ".")
    ProcedureReturn #False
  EndIf
  If ExtraLight <> 0
    WallLightingSetError("Wall lighting: dynamic extralight is deferred; only the static 0 MVP value is supported: " + Str(ExtraLight) + ".")
    ProcedureReturn #False
  EndIf

  shifted = FrontLight >> #LIGHT_SEGSHIFT
  If V1Y = V2Y
    shifted = shifted - 1
  ElseIf V1X = V2X
    shifted = shifted + 1
  EndIf
  If shifted < 0
    shifted = 0
  EndIf
  If shifted >= #LIGHT_LEVELS
    shifted = #LIGHT_LEVELS - 1
  EndIf

  *LightNum\l = shifted
  gWallLighting_LastError = ""
  ProcedureReturn #True
EndProcedure

; Source `index = rw_scale>>LIGHTSCALESHIFT; if index>=MAXLIGHTSCALE -> 47`.
; Production scale is always positive from the M3-05 clamp; a nonpositive value
; is rejected instead of inventing a signed column index.
Procedure.i WallLightingScaleIndexChecked(Scale.l, *ScaleIndex.Long)
  Protected index.l

  WallLightingSetError("")
  If *ScaleIndex = 0
    WallLightingSetError("WallLightingScaleIndexChecked: output pointer is null.")
    ProcedureReturn #False
  EndIf
  If Scale <= 0
    WallLightingSetError("Wall lighting column scale must be positive: " + Str(Scale) + ".")
    ProcedureReturn #False
  EndIf

  index = Scale >> #LIGHT_SCALESHIFT
  If index < 0
    WallLightingSetError("Wall lighting column scale index arithmetic produced a negative value.")
    ProcedureReturn #False
  EndIf
  If index >= #LIGHT_MAXLIGHTSCALE
    index = #LIGHT_MAXLIGHTSCALE - 1
  EndIf

  *ScaleIndex\l = index
  gWallLighting_LastError = ""
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Checked scalelight/COLORMAP texel mapping
; ---------------------------------------------------------------------------

; Table bin lookup: validates table, row and scale index; direct owned Long read.
Procedure.i WallLightingTableMapIndexChecked(*Table.WallScalelightTable,
                                             LightNum.l, ScaleIndex.l,
                                             *MapIndex.Long)
  Protected binIndex.i
  Protected mapIndex.l

  If WallScalelightTableIsValid(*Table) = #False
    WallLightingSetError("Wall lighting table is not initialized.")
    ProcedureReturn #False
  EndIf
  If *Table\MapIndex = 0 Or *Table\Count <> #LIGHT_BinCount Or *Table\Capacity <> #LIGHT_BinCount
    WallLightingSetError("Wall lighting table owned storage/metadata is inconsistent.")
    ProcedureReturn #False
  EndIf
  If LightNum < 0 Or LightNum >= #LIGHT_LEVELS
    WallLightingSetError("Wall lighting table row is outside 0..15: " + Str(LightNum) + ".")
    ProcedureReturn #False
  EndIf
  If ScaleIndex < 0 Or ScaleIndex >= #LIGHT_MAXLIGHTSCALE
    WallLightingSetError("Wall lighting table scale index is outside 0..47: " + Str(ScaleIndex) + ".")
    ProcedureReturn #False
  EndIf

  binIndex = LightNum * #LIGHT_MAXLIGHTSCALE + ScaleIndex
  mapIndex = PeekL(*Table\MapIndex + binIndex * SizeOf(Long))
  If mapIndex < 0 Or mapIndex > #LIGHT_MAXMapIndex
    WallLightingSetError("Wall lighting table map index is outside 0..31: " + Str(mapIndex) + ".")
    ProcedureReturn #False
  EndIf
  If *MapIndex <> 0
    PokeL(*MapIndex, mapIndex)
  EndIf
  gWallLighting_LastError = ""
  ProcedureReturn #True
EndProcedure

; Checked/prevalidated COLORMAP texel lookup: live object validity, >=32 table
; availability, map index 0..31 and palette texel 0..255 are all enforced before
; the direct bounded PeekA. No RGB conversion or table mutation.
Procedure.i WallLightingWallTexelChecked(*Colormap.ColormapSet,
                                         *Table.WallScalelightTable,
                                         LightNum.l, ScaleIndex.l, Texel.l,
                                         *MappedIndex.Long)
  Protected mapIndex.l = 0
  Protected mappedValue.i
  Protected tableOffset.q

  If WallLightingValidateColormap(*Colormap, 0) = #False
    ProcedureReturn #False
  EndIf
  If WallLightingTableMapIndexChecked(*Table, LightNum, ScaleIndex, @mapIndex) = #False
    ProcedureReturn #False
  EndIf
  If Texel < 0 Or Texel > #COLORMAP_TableSize - 1
    WallLightingSetError("Wall lighting source palette texel is outside 0..255: " + Str(Texel) + ".")
    ProcedureReturn #False
  EndIf

  tableOffset.q = Int(mapIndex) * #COLORMAP_TableSize + Int(Texel)
  If tableOffset.q < 0 Or tableOffset.q >= Int(*Colormap\MapCount) * #COLORMAP_TableSize
    WallLightingSetError("Wall lighting COLORMAP texel offset escaped the decoded table array.")
    ProcedureReturn #False
  EndIf
  mappedValue = PeekA(*Colormap\Tables + tableOffset)
  If mappedValue < 0 Or mappedValue > 255
    WallLightingSetError("Wall lighting mapped palette index is outside the palette domain.")
    ProcedureReturn #False
  EndIf

  If *MappedIndex <> 0
    PokeL(*MappedIndex, mappedValue)
  EndIf
  gWallLighting_LastError = ""
  ProcedureReturn #True
EndProcedure

CompilerEndIf
