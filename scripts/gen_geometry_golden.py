#!/usr/bin/env python3
# -----------------------------------------------------------------------------
# DoomPB - independent golden vectors for M3-02 angle/geometry unit tests
# Copyright (C) 2026 DoomPB contributors
# SPDX-License-Identifier: GPL-2.0-only
#
# Optional developer generator. It reads the pinned Linux Doom 1.10 tables.c
# and computes vectors with a separate Python implementation of the original C
# integer algorithms (SlopeDiv, octant angle branches, FixedDiv distance, node
# and seg side tests). It emits only numerical expectations, no C code text and
# no copyrighted resource data. The generated fixture is tracked so an ordinary
# checkout compiles without the local original source tree.
# -----------------------------------------------------------------------------
import argparse
import os
import re
import sys

MASK32 = 0xFFFFFFFF
SIGN32 = 0x80000000
FRACBITS = 16
FRACUNIT = 65536
DBITS = 5
SLOPERANGE = 2048
FINEANGLES = 8192
ANGLETOFINESHIFT = 19
FINEMASK = 8191
ANG45 = 0x20000000
ANG90 = 0x40000000
ANG180 = 0x80000000
ANG270 = 0xC0000000
INT32_MIN = -2147483648
INT32_MAX = 2147483647


def signed32(value):
    low = value & MASK32
    if low >= SIGN32:
        return low - (1 << 32)
    return low


def unsigned32(value):
    return value & MASK32


def trunc_div(numerator, denominator):
    # C-like truncation toward zero (used for the exact integer FixedDiv path).
    if numerator == 0:
        return 0
    magnitude = abs(numerator) // abs(denominator)
    if (numerator < 0) != (denominator < 0):
        return -magnitude
    return magnitude


def parse_c_array(text, name):
    match = re.search(r"\b" + name + r"\[(?:[^\]]*)\]\s*=\s*\{", text)
    if match is None:
        raise ValueError("array %s not found" % name)
    start = text.index("{", match.start())
    end = text.index("};", start)
    tokens = [token.strip() for token in text[start + 1:end].replace("\n", " ").split(",")]
    return [int(token) for token in tokens if token]


def load_tables(source_path):
    with open(source_path, "r", encoding="latin-1") as handle:
        text = handle.read()
    arrays = {name: parse_c_array(text, name) for name in ("finetangent", "finesine", "tantoangle")}
    expected = {
        "finetangent": (4096, -170910304, 170910304),
        "finesine": (10240, 25, 65535),
        "tantoangle": (2049, 0, 536870912),
    }
    for name, (count, first, last) in expected.items():
        values = arrays[name]
        if len(values) != count or values[0] != first or values[-1] != last:
            raise ValueError("%s table does not match the pinned shape" % name)
    return arrays


def slope_div(num, den):
    num = unsigned32(num)
    den = unsigned32(den)
    if den < 512:
        return SLOPERANGE
    answer = ((num << 3) & MASK32) // unsigned32(den >> 8)
    if answer <= SLOPERANGE:
        return answer
    return SLOPERANGE


def fixed_mul_signed(a, b):
    a = signed32(a)
    b = signed32(b)
    product = a * b
    floored = product >> FRACBITS  # Python arithmetic shift, like C signed >>.
    return signed32(floored)


def fixed_div_signed(a, b):
    a = signed32(a)
    b = signed32(b)
    magnitude_a = abs(a)
    magnitude_b = abs(b)
    if (magnitude_a >> 14) >= magnitude_b:
        if (a < 0) != (b < 0):
            return INT32_MIN
        return INT32_MAX
    quotient = trunc_div(a * FRACUNIT, b)
    return signed32(quotient)


def fixed_div_magnitude(num, den):
    # Policy extension for nonnegative magnitudes up to 2^32-1, where the
    # original's signed abs()/int representation is undefined. Same formula and
    # guard, with no possible sign mismatch (both magnitudes nonnegative).
    if (num >> 14) >= den:
        return INT32_MAX
    quotient = num * FRACUNIT // den
    if quotient > INT32_MAX:
        raise ValueError("magnitude quotient escapes the guarded domain")
    return quotient


def point_to_angle(view_x, view_y, x, y, tables):
    delta_x = x - view_x
    delta_y = y - view_y
    if delta_x == 0 and delta_y == 0:
        return 0
    lowered = delta_x >= 0
    raised = delta_y >= 0
    mag_x = delta_x if lowered else -delta_x
    mag_y = delta_y if raised else -delta_y
    if mag_x > mag_y:
        atan = tables["tantoangle"][slope_div(mag_y, mag_x)]
    else:
        atan = tables["tantoangle"][slope_div(mag_x, mag_y)]
    if lowered:
        if raised:
            if mag_x > mag_y:
                return unsigned32(atan)
            return unsigned32(ANG90 - 1 - atan)
        if mag_x > mag_y:
            return unsigned32(-atan)
        return unsigned32(ANG270 + atan)
    if raised:
        if mag_x > mag_y:
            return unsigned32(ANG180 - 1 - atan)
        return unsigned32(ANG90 + atan)
    if mag_x > mag_y:
        return unsigned32(ANG180 + atan)
    return unsigned32(ANG270 - 1 - atan)


def point_to_dist(view_x, view_y, x, y, tables):
    dx = x - view_x
    dy = y - view_y
    mag_dx = dx if dx >= 0 else -dx
    mag_dy = dy if dy >= 0 else -dy
    if mag_dy > mag_dx:
        mag_dx, mag_dy = mag_dy, mag_dx
    if mag_dx == 0:
        return 0, True  # DoomPB deterministic coincident-point policy.
    extended = mag_dx > INT32_MAX or mag_dy > INT32_MAX
    ratio = fixed_div_magnitude(mag_dy, mag_dx) if extended else fixed_div_signed(mag_dy, mag_dx)
    if ratio < 0:
        raise ValueError("distance slope ratio is negative")
    slope_index = ratio >> DBITS
    if slope_index < 0 or slope_index > SLOPERANGE:
        raise ValueError("distance slope index %d out of tantoangle domain" % slope_index)
    atan = tables["tantoangle"][slope_index]
    fine_angle = unsigned32((atan + ANG90) & MASK32) >> ANGLETOFINESHIFT
    if fine_angle < 2048 or fine_angle > 3072:
        raise ValueError("distance cosine index %d out of expected sine domain" % fine_angle)
    cosine = tables["finesine"][fine_angle]
    if cosine == 0:
        raise ValueError("distance cosine is zero")
    if extended:
        return fixed_div_magnitude(mag_dx, cosine), True
    return fixed_div_signed(mag_dx, cosine), True


def sign_bit(value):
    return bool(unsigned32(value) & SIGN32)


def point_side(x, y, origin_x, origin_y, line_dx, line_dy):
    if line_dx == 0:
        if x <= origin_x:
            return 1 if line_dy > 0 else 0
        return 1 if line_dy < 0 else 0
    if line_dy == 0:
        if y <= origin_y:
            return 1 if line_dx < 0 else 0
        return 1 if line_dx > 0 else 0
    dx = x - origin_x
    dy = y - origin_y
    if sign_bit(line_dy) ^ sign_bit(line_dx) ^ sign_bit(dx) ^ sign_bit(dy):
        if sign_bit(line_dy) ^ sign_bit(dx):
            return 1
        return 0
    left = fixed_mul_signed(line_dy >> FRACBITS, dx)
    right = fixed_mul_signed(dy, line_dx >> FRACBITS)
    if right < left:
        return 0
    return 1


def default_source():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)
    return os.path.join(repo_root, "..", "doom-original", "linuxdoom-1.10", "tables.c")


def collect_vectors(tables):
    slope = [
        (0, 0), (0, 511), (1000, 0), (1000, 511), (1000, 12345),
        (0, 512), (256, 512), (512, 512), (256, 513), (512, 513),
        (511, 512), (512, 512), (100000, 512), (2047, 512), (2048, 512),
        (640, 640), (1024, 1024), (32768, 65536), (65535, 65536),
        (65536, 65536), (65537, 65536), (16383, 16384), (16384, 16384),
        (2147483648, 2147483648), (4294967295, 4294967295),
        (4294967295, 512), (1073741824, 2147483648),
    ]

    # Angle vectors. Ordinary vectors stay inside the C defined signed32 delta
    # domain; the INT32_MIN delta vector uses the documented unsigned-magnitude
    # policy (C negation/abs is undefined there).
    angle = [
        (0, 0, 0, 0),
        (0, 0, 65536, 0),
        (0, 0, 0, 65536),
        (0, 0, -65536, 0),
        (0, 0, 0, -65536),
        (0, 0, 65536, 65536),
        (0, 0, 65536, -65536),
        (0, 0, -65536, 65536),
        (0, 0, -65536, -65536),
        (0, 0, 65537, 65536),
        (0, 0, 65536, 65537),
        (0, 0, 65536, 65535),
        (0, 0, 65535, 65536),
        (0, 0, -65537, -65536),
        (0, 0, -65536, -65537),
        (0, 0, 65536, 1),
        (0, 0, 1, 65536),
        (0, 0, -65536, 1),
        (0, 0, 1, -65536),
        (100000, 200000, 300000, 350000),
        (100000, 200000, -300000, 350000),
        (100000, 200000, 300000, -350000),
        (100000, 200000, -300000, -350000),
        (-200000, 100000, 0, 0),
        (-200000, 100000, 100000, 100000),
        (65536, -65536, 0, 0),
        (2000000000, 0, 2147483647, 0),
        (0, 2000000000, 2147483647, 0),
        (2000000000, 2000000000, 2147483647, 2147483647),
        (2147483647, 0, 1, 0),
        (0, 0, -2147483648, 0),
    ]

    # Distance vectors: valid exact outputs, the coincident-point policy, and
    # the documented magnitude extension for an INT32_MIN delta.
    distance = [
        (0, 0, 0, 0),
        (0, 0, 65536, 0),
        (0, 0, -65536, 0),
        (0, 0, 0, 65536),
        (0, 0, 0, -65536),
        (0, 0, 65536, 65536),
        (0, 0, 65536, -65536),
        (0, 0, -65536, 65536),
        (0, 0, -65536, -65536),
        (0, 0, 65536, 32768),
        (0, 0, 32768, 65536),
        (0, 0, 1, 1),
        (0, 0, 3, 1),
        (0, 0, 1, 3),
        (100000, 200000, 300000, 350000),
        (100000, 200000, -300000, -350000),
        (-200000, 100000, 200000, 100000),
        (65536, -65536, -65536, 65536),
        (0, 0, 2000000000, 1000000000),
        (0, 0, 1000000000, 2000000000),
        (0, 0, 2147483647, 2147483647),
        (0, 0, -2147483648, 0),
    ]

    side = [
        # node/seg line: origin plus fixed partition direction.
        (65536, 65536, 65536, 0, 0, 65536),  # vertical dx=0, positive dy, on boundary
        (65537, 65536, 65536, 0, 0, 65536),  # vertical dx=0, positive dy, right of origin
        (65535, 65536, 65536, 0, 0, 65536),  # vertical dx=0, positive dy, left of origin
        (65536, 65536, 65536, 0, 0, -65536),  # vertical dx=0, negative dy, on boundary
        (65537, 65536, 65536, 0, 0, -65536),
        (65535, 65536, 65536, 0, 0, -65536),
        (65536, 65536, 0, 65536, 65536, 0),  # horizontal dy=0, positive dx, on boundary
        (65536, 65537, 0, 65536, 65536, 0),
        (65536, 65535, 0, 65536, 65536, 0),
        (65536, 65536, 0, 65536, -65536, 0),  # horizontal dy=0, negative dx
        (65536, 65537, 0, 65536, -65536, 0),
        (65536, 65535, 0, 65536, -65536, 0),
        (65536, 65536, 0, 0, 65536, 65536),  # sloped exactly on line, equality tie
        (65537, 65536, 0, 0, 65536, 65536),  # one LSB above the line
        (65536, 65537, 0, 0, 65536, 65536),
        (65536, 65535, 0, 0, 65536, 65536),
        (65536, 65536, 0, 0, -65536, 65536),  # signs / shortcut vectors
        (65536, 65536, 0, 0, 65536, -65536),
        (-65536, -65536, 0, 0, 65536, 65536),
        (-65536, 65536, 0, 0, 65536, 65536),
        (65536, -65536, 0, 0, 65536, 65536),
        (32768, 65536, 0, 0, 65536, 65536),
        (65536, 32768, 0, 0, 65536, 65536),
        (65536, 65536, 0, 0, 65536, 32768),
        (65536, 65536, 0, 0, 32768, 65536),
        (65536, 65536, -65536, -65536, 65536, 65536),
        (65535, 65536, -65536, -65536, 65536, 65536),
        # explicit reversed/mirrored endpoint orientation pairs
        (65536, 65536, 65536, 65536, -65536, -65536),
        (65537, 65536, 65536, 65536, -65536, -65536),
        (65535, 65536, 65536, 65536, -65536, -65536),
    ]

    slope_expected = [slope_div(n, d) for n, d in slope]
    angle_expected = [point_to_angle(vx, vy, x, y, tables) for vx, vy, x, y in angle]
    distance_expected = []
    for vx, vy, x, y in distance:
        value, ok = point_to_dist(vx, vy, x, y, tables)
        distance_expected.append((value, ok))
    side_expected = [point_side(x, y, ox, oy, ldx, ldy) for x, y, ox, oy, ldx, ldy in side]
    return slope, slope_expected, angle, angle_expected, distance, distance_expected, side, side_expected


def main():
    parser = argparse.ArgumentParser(description="Generate DoomPB M3-02 independent golden vectors")
    parser.add_argument("--source", default=default_source(), help="path to pinned tables.c")
    parser.add_argument("--output", default="", help="output .pbi path (default: tests/fixtures)")
    args = parser.parse_args()

    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)
    source_path = os.path.abspath(args.source)
    output_path = os.path.abspath(args.output) if args.output else os.path.join(repo_root, "tests", "fixtures", "m3_geometry_golden.pbi")
    if not os.path.isfile(source_path):
        print("error: pinned tables.c not found at %s" % source_path, file=sys.stderr)
        return 1

    try:
        tables = load_tables(source_path)
        vectors = collect_vectors(tables)
    except ValueError as error:
        print("error: %s" % error, file=sys.stderr)
        return 1

    slope, slope_expected, angle, angle_expected, distance, distance_expected, side, side_expected = vectors

    lines = []
    lines.append("; -----------------------------------------------------------------------------")
    lines.append("; DoomPB - independent M3-02 golden vectors (generated fixture)")
    lines.append("; Copyright (C) 2026 DoomPB contributors")
    lines.append("; SPDX-License-Identifier: GPL-2.0-only")
    lines.append(";")
    lines.append("; Provenance: scripts/gen_geometry_golden.py reads the pinned")
    lines.append("; ../doom-original/linuxdoom-1.10/tables.c (commit")
    lines.append("; a77dfb96cb91780ca334d0d4cfd86957558007e0) and uses a separate Python")
    lines.append("; integer oracle for the original algorithms. DoomPB never reads this")
    lines.append("; fixture generator at build/runtime; expectations are numeric only and")
    lines.append("; contain no game graphics, payload bytes or copyrighted resources.")
    lines.append("; Do not hand-edit; regenerate with scripts/gen_geometry_golden.py.")
    lines.append("; The INT32_MIN delta vectors use the documented unsigned-magnitude")
    lines.append("; policy where the original C negation/abs operations are undefined.")
    lines.append("; -----------------------------------------------------------------------------")
    lines.append("")
    lines.append("CompilerIf Defined(DOOMPB_GEOGOLD_PBI, #PB_Constant) = 0")
    lines.append("")
    lines.append("#DOOMPB_GEOGOLD_PBI = 1")
    lines.append("")
    lines.append("#GEOGOLD_SlopeCount = %d" % len(slope))
    lines.append("#GEOGOLD_AngleCount = %d" % len(angle))
    lines.append("#GEOGOLD_DistanceCount = %d" % len(distance))
    lines.append("#GEOGOLD_SideCount = %d" % len(side))
    lines.append("")
    lines.append("DataSection")
    lines.append("  GeoGoldSlopeNum:")
    for offset in range(0, len(slope), 8):
        chunk = slope[offset:offset + 8]
        lines.append("  Data.q " + ", ".join(str(n) for n, _ in chunk))
    lines.append("  GeoGoldSlopeDen:")
    for offset in range(0, len(slope), 8):
        chunk = slope[offset:offset + 8]
        lines.append("  Data.q " + ", ".join(str(d) for _, d in chunk))
    lines.append("  GeoGoldSlopeExpected:")
    for offset in range(0, len(slope_expected), 8):
        chunk = slope_expected[offset:offset + 8]
        lines.append("  Data.l " + ", ".join(str(v) for v in chunk))
    lines.append("  GeoGoldAngleViewX:")
    for offset in range(0, len(angle), 8):
        chunk = angle[offset:offset + 8]
        lines.append("  Data.l " + ", ".join(str(vx) for vx, _, _, _ in chunk))
    lines.append("  GeoGoldAngleViewY:")
    for offset in range(0, len(angle), 8):
        chunk = angle[offset:offset + 8]
        lines.append("  Data.l " + ", ".join(str(vy) for _, vy, _, _ in chunk))
    lines.append("  GeoGoldAngleX:")
    for offset in range(0, len(angle), 8):
        chunk = angle[offset:offset + 8]
        lines.append("  Data.l " + ", ".join(str(x) for _, _, x, _ in chunk))
    lines.append("  GeoGoldAngleY:")
    for offset in range(0, len(angle), 8):
        chunk = angle[offset:offset + 8]
        lines.append("  Data.l " + ", ".join(str(y) for _, _, _, y in chunk))
    lines.append("  GeoGoldAngleExpected:")
    for offset in range(0, len(angle_expected), 8):
        chunk = angle_expected[offset:offset + 8]
        lines.append("  Data.q " + ", ".join(str(v) for v in chunk))
    lines.append("  GeoGoldDistanceViewX:")
    for offset in range(0, len(distance), 8):
        chunk = distance[offset:offset + 8]
        lines.append("  Data.l " + ", ".join(str(vx) for vx, _, _, _ in chunk))
    lines.append("  GeoGoldDistanceViewY:")
    for offset in range(0, len(distance), 8):
        chunk = distance[offset:offset + 8]
        lines.append("  Data.l " + ", ".join(str(vy) for _, vy, _, _ in chunk))
    lines.append("  GeoGoldDistanceX:")
    for offset in range(0, len(distance), 8):
        chunk = distance[offset:offset + 8]
        lines.append("  Data.l " + ", ".join(str(x) for _, _, x, _ in chunk))
    lines.append("  GeoGoldDistanceY:")
    for offset in range(0, len(distance), 8):
        chunk = distance[offset:offset + 8]
        lines.append("  Data.l " + ", ".join(str(y) for _, _, _, y in chunk))
    lines.append("  GeoGoldDistanceExpected:")
    for offset in range(0, len(distance_expected), 8):
        chunk = distance_expected[offset:offset + 8]
        lines.append("  Data.l " + ", ".join(str(v) for v, _ in chunk))
    lines.append("  GeoGoldDistanceOk:")
    for offset in range(0, len(distance_expected), 8):
        chunk = distance_expected[offset:offset + 8]
        lines.append("  Data.l " + ", ".join(str(1 if ok else 0) for _, ok in chunk))
    lines.append("  GeoGoldSideX:")
    for offset in range(0, len(side), 8):
        chunk = side[offset:offset + 8]
        lines.append("  Data.l " + ", ".join(str(x) for x, _, _, _, _, _ in chunk))
    lines.append("  GeoGoldSideY:")
    for offset in range(0, len(side), 8):
        chunk = side[offset:offset + 8]
        lines.append("  Data.l " + ", ".join(str(y) for _, y, _, _, _, _ in chunk))
    lines.append("  GeoGoldSideOriginX:")
    for offset in range(0, len(side), 8):
        chunk = side[offset:offset + 8]
        lines.append("  Data.l " + ", ".join(str(ox) for _, _, ox, _, _, _ in chunk))
    lines.append("  GeoGoldSideOriginY:")
    for offset in range(0, len(side), 8):
        chunk = side[offset:offset + 8]
        lines.append("  Data.l " + ", ".join(str(oy) for _, _, _, oy, _, _ in chunk))
    lines.append("  GeoGoldSideLineDX:")
    for offset in range(0, len(side), 8):
        chunk = side[offset:offset + 8]
        lines.append("  Data.l " + ", ".join(str(ldx) for _, _, _, _, ldx, _ in chunk))
    lines.append("  GeoGoldSideLineDY:")
    for offset in range(0, len(side), 8):
        chunk = side[offset:offset + 8]
        lines.append("  Data.l " + ", ".join(str(ldy) for _, _, _, _, _, ldy in chunk))
    lines.append("  GeoGoldSideExpected:")
    for offset in range(0, len(side_expected), 8):
        chunk = side_expected[offset:offset + 8]
        lines.append("  Data.l " + ", ".join(str(v) for v in chunk))
    lines.append("EndDataSection")
    lines.append("")
    lines.append("Global *gGeoGoldSlopeNum = ?GeoGoldSlopeNum")
    lines.append("Global *gGeoGoldSlopeDen = ?GeoGoldSlopeDen")
    lines.append("Global *gGeoGoldSlopeExpected = ?GeoGoldSlopeExpected")
    lines.append("Global *gGeoGoldAngleViewX = ?GeoGoldAngleViewX")
    lines.append("Global *gGeoGoldAngleViewY = ?GeoGoldAngleViewY")
    lines.append("Global *gGeoGoldAngleX = ?GeoGoldAngleX")
    lines.append("Global *gGeoGoldAngleY = ?GeoGoldAngleY")
    lines.append("Global *gGeoGoldAngleExpected = ?GeoGoldAngleExpected")
    lines.append("Global *gGeoGoldDistanceViewX = ?GeoGoldDistanceViewX")
    lines.append("Global *gGeoGoldDistanceViewY = ?GeoGoldDistanceViewY")
    lines.append("Global *gGeoGoldDistanceX = ?GeoGoldDistanceX")
    lines.append("Global *gGeoGoldDistanceY = ?GeoGoldDistanceY")
    lines.append("Global *gGeoGoldDistanceExpected = ?GeoGoldDistanceExpected")
    lines.append("Global *gGeoGoldDistanceOk = ?GeoGoldDistanceOk")
    lines.append("Global *gGeoGoldSideX = ?GeoGoldSideX")
    lines.append("Global *gGeoGoldSideY = ?GeoGoldSideY")
    lines.append("Global *gGeoGoldSideOriginX = ?GeoGoldSideOriginX")
    lines.append("Global *gGeoGoldSideOriginY = ?GeoGoldSideOriginY")
    lines.append("Global *gGeoGoldSideLineDX = ?GeoGoldSideLineDX")
    lines.append("Global *gGeoGoldSideLineDY = ?GeoGoldSideLineDY")
    lines.append("Global *gGeoGoldSideExpected = ?GeoGoldSideExpected")
    lines.append("")
    lines.append("CompilerEndIf")
    lines.append("")

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="ascii", newline="\n") as handle:
        handle.write("\n".join(lines))

    print("slope %d, angle %d, distance %d, side %d" % (len(slope), len(angle), len(distance), len(side)))
    print("wrote %s" % output_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
