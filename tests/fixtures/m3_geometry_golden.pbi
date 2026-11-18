; -----------------------------------------------------------------------------
; DoomPB - independent M3-02 golden vectors (generated fixture)
; Copyright (C) 2026 DoomPB contributors
; SPDX-License-Identifier: GPL-2.0-only
;
; Provenance: scripts/gen_geometry_golden.py reads the pinned
; ../doom-original/linuxdoom-1.10/tables.c (commit
; a77dfb96cb91780ca334d0d4cfd86957558007e0) and uses a separate Python
; integer oracle for the original algorithms. DoomPB never reads this
; fixture generator at build/runtime; expectations are numeric only and
; contain no game graphics, payload bytes or copyrighted resources.
; Do not hand-edit; regenerate with scripts/gen_geometry_golden.py.
; The INT32_MIN delta vectors use the documented unsigned-magnitude
; policy where the original C negation/abs operations are undefined.
; -----------------------------------------------------------------------------

CompilerIf Defined(DOOMPB_GEOGOLD_PBI, #PB_Constant) = 0

#DOOMPB_GEOGOLD_PBI = 1

#GEOGOLD_SlopeCount = 27
#GEOGOLD_AngleCount = 31
#GEOGOLD_DistanceCount = 22
#GEOGOLD_SideCount = 30

DataSection
  GeoGoldSlopeNum:
  Data.q 0, 0, 1000, 1000, 1000, 0, 256, 512
  Data.q 256, 512, 511, 512, 100000, 2047, 2048, 640
  Data.q 1024, 32768, 65535, 65536, 65537, 16383, 16384, 2147483648
  Data.q 4294967295, 4294967295, 1073741824
  GeoGoldSlopeDen:
  Data.q 0, 511, 0, 511, 12345, 512, 512, 512
  Data.q 513, 513, 512, 512, 512, 512, 512, 640
  Data.q 1024, 65536, 65536, 65536, 65536, 16384, 16384, 2147483648
  Data.q 4294967295, 512, 2147483648
  GeoGoldSlopeExpected:
  Data.l 2048, 2048, 2048, 2048, 166, 0, 1024, 2048
  Data.l 1024, 2048, 2044, 2048, 2048, 2048, 2048, 2048
  Data.l 2048, 1024, 2047, 2048, 2048, 2047, 2048, 0
  Data.l 256, 2048, 0
  GeoGoldAngleViewX:
  Data.l 0, 0, 0, 0, 0, 0, 0, 0
  Data.l 0, 0, 0, 0, 0, 0, 0, 0
  Data.l 0, 0, 0, 100000, 100000, 100000, 100000, -200000
  Data.l -200000, 65536, 2000000000, 0, 2000000000, 2147483647, 0
  GeoGoldAngleViewY:
  Data.l 0, 0, 0, 0, 0, 0, 0, 0
  Data.l 0, 0, 0, 0, 0, 0, 0, 0
  Data.l 0, 0, 0, 200000, 200000, 200000, 200000, 100000
  Data.l 100000, -65536, 0, 2000000000, 2000000000, 0, 0
  GeoGoldAngleX:
  Data.l 0, 65536, 0, -65536, 0, 65536, 65536, -65536
  Data.l -65536, 65537, 65536, 65536, 65535, -65537, -65536, 65536
  Data.l 1, -65536, 1, 300000, -300000, 300000, -300000, 0
  Data.l 100000, 0, 2147483647, 2147483647, 2147483647, 1, -2147483648
  GeoGoldAngleY:
  Data.l 0, 0, 65536, 0, -65536, 65536, -65536, 65536
  Data.l -65536, 65536, 65537, 65535, 65536, -65536, -65537, 1
  Data.l 65536, 1, -65536, 350000, 350000, -350000, -350000, 0
  Data.l 100000, 0, 0, 0, 2147483647, 0, 0
  GeoGoldAngleExpected:
  Data.q 0, 0, 1073741823, 2147483647, 3221225472, 536870911, 3758096384, 1610612736
  Data.q 2684354559, 536870912, 536870911, 536704000, 537037823, 2684354560, 2684354559, 0
  Data.q 1073741823, 2147483647, 3221225472, 439875008, 1902240479, 3459418800, 2791501407, 3978033888
  Data.q 0, 1610612736, 0, 4172466320, 536870911, 2147483647, 2147483647
  GeoGoldDistanceViewX:
  Data.l 0, 0, 0, 0, 0, 0, 0, 0
  Data.l 0, 0, 0, 0, 0, 0, 100000, 100000
  Data.l -200000, 65536, 0, 0, 0, 0
  GeoGoldDistanceViewY:
  Data.l 0, 0, 0, 0, 0, 0, 0, 0
  Data.l 0, 0, 0, 0, 0, 0, 200000, 200000
  Data.l 100000, -65536, 0, 0, 0, 0
  GeoGoldDistanceX:
  Data.l 0, 65536, -65536, 0, 0, 65536, 65536, -65536
  Data.l -65536, 65536, 32768, 1, 3, 1, 300000, -300000
  Data.l 200000, -65536, 2000000000, 1000000000, 2147483647, -2147483648
  GeoGoldDistanceY:
  Data.l 0, 0, 0, 65536, -65536, 65536, -65536, 65536
  Data.l -65536, 32768, 65536, 1, 1, 3, 350000, -350000
  Data.l 100000, 65536, 1000000000, 2000000000, 2147483647, 0
  GeoGoldDistanceExpected:
  Data.l 0, 65537, 65537, 65537, 65537, 92717, 92717, 92717
  Data.l 92717, 73271, 73271, 1, 3, 3, 249932, 679962
  Data.l 400006, 185435, 2147483647, 2147483647, 2147483647, 2147483647
  GeoGoldDistanceOk:
  Data.l 1, 1, 1, 1, 1, 1, 1, 1
  Data.l 1, 1, 1, 1, 1, 1, 1, 1
  Data.l 1, 1, 1, 1, 1, 1
  GeoGoldSideX:
  Data.l 65536, 65537, 65535, 65536, 65537, 65535, 65536, 65536
  Data.l 65536, 65536, 65536, 65536, 65536, 65537, 65536, 65536
  Data.l 65536, 65536, -65536, -65536, 65536, 32768, 65536, 65536
  Data.l 65536, 65536, 65535, 65536, 65537, 65535
  GeoGoldSideY:
  Data.l 65536, 65536, 65536, 65536, 65536, 65536, 65536, 65537
  Data.l 65535, 65536, 65537, 65535, 65536, 65536, 65537, 65535
  Data.l 65536, 65536, -65536, 65536, -65536, 65536, 32768, 65536
  Data.l 65536, 65536, 65536, 65536, 65536, 65536
  GeoGoldSideOriginX:
  Data.l 65536, 65536, 65536, 65536, 65536, 65536, 0, 0
  Data.l 0, 0, 0, 0, 0, 0, 0, 0
  Data.l 0, 0, 0, 0, 0, 0, 0, 0
  Data.l 0, -65536, -65536, 65536, 65536, 65536
  GeoGoldSideOriginY:
  Data.l 0, 0, 0, 0, 0, 0, 65536, 65536
  Data.l 65536, 65536, 65536, 65536, 0, 0, 0, 0
  Data.l 0, 0, 0, 0, 0, 0, 0, 0
  Data.l 0, -65536, -65536, 65536, 65536, 65536
  GeoGoldSideLineDX:
  Data.l 0, 0, 0, 0, 0, 0, 65536, 65536
  Data.l 65536, -65536, -65536, -65536, 65536, 65536, 65536, 65536
  Data.l -65536, 65536, 65536, 65536, 65536, 65536, 65536, 65536
  Data.l 32768, 65536, 65536, -65536, -65536, -65536
  GeoGoldSideLineDY:
  Data.l 65536, 65536, 65536, -65536, -65536, -65536, 0, 0
  Data.l 0, 0, 0, 0, 65536, 65536, 65536, 65536
  Data.l 65536, -65536, 65536, 65536, 65536, 65536, 65536, 32768
  Data.l 65536, 65536, 65536, -65536, -65536, -65536
  GeoGoldSideExpected:
  Data.l 1, 0, 1, 0, 1, 0, 0, 1
  Data.l 0, 1, 0, 1, 1, 1, 1, 0
  Data.l 0, 1, 1, 1, 0, 1, 0, 1
  Data.l 0, 1, 1, 1, 1, 0
EndDataSection

Global *gGeoGoldSlopeNum = ?GeoGoldSlopeNum
Global *gGeoGoldSlopeDen = ?GeoGoldSlopeDen
Global *gGeoGoldSlopeExpected = ?GeoGoldSlopeExpected
Global *gGeoGoldAngleViewX = ?GeoGoldAngleViewX
Global *gGeoGoldAngleViewY = ?GeoGoldAngleViewY
Global *gGeoGoldAngleX = ?GeoGoldAngleX
Global *gGeoGoldAngleY = ?GeoGoldAngleY
Global *gGeoGoldAngleExpected = ?GeoGoldAngleExpected
Global *gGeoGoldDistanceViewX = ?GeoGoldDistanceViewX
Global *gGeoGoldDistanceViewY = ?GeoGoldDistanceViewY
Global *gGeoGoldDistanceX = ?GeoGoldDistanceX
Global *gGeoGoldDistanceY = ?GeoGoldDistanceY
Global *gGeoGoldDistanceExpected = ?GeoGoldDistanceExpected
Global *gGeoGoldDistanceOk = ?GeoGoldDistanceOk
Global *gGeoGoldSideX = ?GeoGoldSideX
Global *gGeoGoldSideY = ?GeoGoldSideY
Global *gGeoGoldSideOriginX = ?GeoGoldSideOriginX
Global *gGeoGoldSideOriginY = ?GeoGoldSideOriginY
Global *gGeoGoldSideLineDX = ?GeoGoldSideLineDX
Global *gGeoGoldSideLineDY = ?GeoGoldSideLineDY
Global *gGeoGoldSideExpected = ?GeoGoldSideExpected

CompilerEndIf
