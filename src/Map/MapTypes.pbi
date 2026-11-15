; -----------------------------------------------------------------------------
; DoomPB - a native PureBasic source port of Doom
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Vanilla Doom map binary types and constants.
;
; On-disk map records are packed little-endian. The native structures below are
; deliberately NOT packed copies: every field is decoded explicitly and stored
; in a .l (or byte array) so later stages can use them without alignment or
; endianness assumptions.
;
; This module owns types/limits only. Decoding lives in MapDecode.pbi and
; Blockmap.pbi; cross-lump reference validation belongs to M2-06.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_MAPTYPES_PBI, #PB_Constant) = 0

#DOOMPB_MAPTYPES_PBI = 1

; Vanilla map marker + ten following lumps.
Enumeration MapLumpKind
  #MAP_KindNone
  #MAP_KindThings
  #MAP_KindLinedefs
  #MAP_KindSidedefs
  #MAP_KindVertexes
  #MAP_KindSegs
  #MAP_KindSubsectors
  #MAP_KindNodes
  #MAP_KindSectors
  #MAP_KindReject
  #MAP_KindBlockmap
EndEnumeration

; Exact on-disk record sizes.
#MAP_ThingSize       = 10
#MAP_LinedefSize     = 14
#MAP_SidedefSize     = 30
#MAP_VertexSize      = 4
#MAP_SegSize         = 12
#MAP_SubsectorSize   = 4
#MAP_NodeSize        = 28
#MAP_SectorSize      = 26

; Vanilla constants needed by the raw representation.
#MAP_NF_SUBSECTOR    = $8000
#MAP_ML_BLOCKING     = 1
#MAP_ML_BLOCKMONSTERS = 2
#MAP_ML_TWOSIDED     = 4
#MAP_ML_DONTPEGTOP   = 8
#MAP_ML_DONTPEGBOTTOM = 16
#MAP_ML_SECRET       = 32
#MAP_ML_SOUNDBLOCK   = 64
#MAP_ML_DONTDRAW     = 128
#MAP_ML_MAPPED       = 256

; Safety budgets (project policy, not format limits).
#MAP_MaxRecords      = 65536
#MAP_MaxBlockmapCells = 1048576
#MAP_MaxBlockmapScanWords = 16000000

#MAP_RecordsMagic    = $4D415031
#MAP_RejectMagic     = $4D525031
#MAP_BlockmapMagic   = $4D424D31

Structure MapThing
  X.l
  Y.l
  Angle.l
  Type.l
  Options.l
EndStructure

Structure MapLinedef
  V1.l
  V2.l
  Flags.l
  Special.l
  Tag.l
  Side0.l
  Side1.l
EndStructure

Structure MapSidedef
  TextureOffset.l
  RowOffset.l
  TopTexture.a[8]
  BottomTexture.a[8]
  MidTexture.a[8]
  Sector.l
EndStructure

Structure MapVertex
  X.l
  Y.l
EndStructure

Structure MapSeg
  V1.l
  V2.l
  Angle.l
  Linedef.l
  Side.l
  Offset.l
EndStructure

Structure MapSubsector
  NumSegs.l
  FirstSeg.l
EndStructure

Structure MapNode
  X.l
  Y.l
  DX.l
  DY.l
  Box0Top.l
  Box0Bottom.l
  Box0Left.l
  Box0Right.l
  Box1Top.l
  Box1Bottom.l
  Box1Left.l
  Box1Right.l
  Child0.l
  Child1.l
EndStructure

Structure MapSector
  FloorHeight.l
  CeilingHeight.l
  FloorPic.a[8]
  CeilingPic.a[8]
  LightLevel.l
  Special.l
  Tag.l
EndStructure

Structure MapThingSet
  Magic.l
  Count.l
  *Items.MapThing
EndStructure

Structure MapLinedefSet
  Magic.l
  Count.l
  *Items.MapLinedef
EndStructure

Structure MapSidedefSet
  Magic.l
  Count.l
  *Items.MapSidedef
EndStructure

Structure MapVertexSet
  Magic.l
  Count.l
  *Items.MapVertex
EndStructure

Structure MapSegSet
  Magic.l
  Count.l
  *Items.MapSeg
EndStructure

Structure MapSubsectorSet
  Magic.l
  Count.l
  *Items.MapSubsector
EndStructure

Structure MapNodeSet
  Magic.l
  Count.l
  *Items.MapNode
EndStructure

Structure MapSectorSet
  Magic.l
  Count.l
  *Items.MapSector
EndStructure

Structure MapReject
  Magic.l
  Size.q
  *Bytes.Byte
EndStructure

Structure MapBlockmap
  Magic.l
  OriginX.l
  OriginY.l
  Width.l
  Height.l
  Size.q
  *Bytes.Byte
EndStructure

CompilerEndIf
