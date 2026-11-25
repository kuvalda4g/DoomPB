#!/usr/bin/env python3
# -----------------------------------------------------------------------------
# DoomPB - independent M3-04 classic projection fixture generator
# Copyright (C) 2026 DoomPB contributors
# SPDX-License-Identifier: GPL-2.0-only
#
"""
DoomPB - independent M3-04 classic projection fixture generator.

Provenance: reads the pinned ../doom-original/linuxdoom-1.10/tables.c values
(commit a77dfb96cb91780ca334d0d4cfd86957558007e0) and computes viewangletox,
xtoviewangle, clipangle and constants with a separate pure-integer Python
oracle implementing the original r_main.c R_InitTextureMapping operation order.
The committed fixture contains numeric table values/hashes only; it is not
WAD-derived game data, graphics or copyrighted resource payload.

The oracle is test-only generation logic. DoomPB production and tests never
execute this Python script; regeneration is deterministic. Do not hand-edit.
"""
import argparse
import os
import re

MASK32 = 0xFFFFFFFF
SIGN32 = 0x80000000
FRACBITS = 16
FRACUNIT = 1 << FRACBITS
INT32_MIN = -2147483648
INT32_MAX = 2147483647
ANG90 = 0x40000000
FINEANGLES = 8192
ANGLETOFINESHIFT = 19
FIELDOFVIEW = 2048
VIEWWIDTH = 320
VIEWHEIGHT = 200
CENTERX = VIEWWIDTH // 2
CENTERY = VIEWHEIGHT // 2
CENTERXFIXED = CENTERX << FRACBITS
CENTERYFIXED = CENTERY << FRACBITS
PROJECTIONFIXED = CENTERXFIXED
FOCAL_INDEX = FINEANGLES // 4 + FIELDOFVIEW // 2
FNV_OFFSET = 14695981039346656037
FNV_PRIME = 1099511628211


def unsigned32(value):
    return value & MASK32


def signed32(value):
    low = value & MASK32
    if low >= SIGN32:
        return low - (1 << 32)
    return low


def trunc_div(numerator, denominator):
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


def load_tangent(source_path):
    with open(source_path, "r", encoding="latin-1") as handle:
        text = handle.read()
    values = parse_c_array(text, "finetangent")
    if len(values) != 4096 or values[0] != -170910304 or values[-1] != 170910304:
        raise ValueError("finetangent table does not match the pinned shape")
    return values


def fixed_mul(a, b):
    a = signed32(a)
    b = signed32(b)
    return signed32(a * b >> FRACBITS)


def fixed_div(a, b):
    a = signed32(a)
    b = signed32(b)
    magnitude_a = abs(a)
    magnitude_b = abs(b)
    if (magnitude_a >> 14) >= magnitude_b:
        return INT32_MIN if (a < 0) != (b < 0) else INT32_MAX
    return signed32(trunc_div(a * FRACUNIT, b))


def fence(tangent):
    if tangent > FRACUNIT * 2:
        return -1, 1
    if tangent < -FRACUNIT * 2:
        return VIEWWIDTH + 1, 2
    return 0, 0


def build_projection(tangent):
    focal = fixed_div(CENTERXFIXED, tangent[FOCAL_INDEX])
    pre = []
    kind = []
    for value in tangent:
        fenced, fence_kind = fence(value)
        kind.append(fence_kind)
        if fence_kind:
            pre.append(fenced)
            continue
        scaled = fixed_mul(value, focal)
        member = CENTERXFIXED - scaled + FRACUNIT - 1
        t = signed32(member >> FRACBITS)
        t = max(-1, min(VIEWWIDTH + 1, t))
        pre.append(t)
    inverse = []
    for x in range(VIEWWIDTH + 1):
        index = 0
        while index < len(pre) and pre[index] > x:
            index += 1
        if index >= len(pre):
            raise ValueError("viewangletox did not cross column %d" % x)
        inverse.append(unsigned32((index << ANGLETOFINESHIFT) - ANG90))
    post = []
    for value in pre:
        if value == -1:
            post.append(0)
        elif value == VIEWWIDTH + 1:
            post.append(VIEWWIDTH)
        else:
            post.append(value)
    clip = inverse[0]
    return focal, pre, post, inverse, kind, clip


def fnv_long(hash_value, value):
    value = signed32(value)
    for shift in (0, 8, 16, 24):
        hash_value = (hash_value ^ ((value >> shift) & 0xFF)) * FNV_PRIME
        hash_value &= 0xFFFFFFFFFFFFFFFF
    return hash_value


def fnv_unsigned_long(hash_value, value):
    value = unsigned32(value)
    for shift in (0, 8, 16, 24):
        hash_value = (hash_value ^ ((value >> shift) & 0xFF)) * FNV_PRIME
        hash_value &= 0xFFFFFFFFFFFFFFFF
    return hash_value


def hash_array(values, unsigned=False):
    hash_value = FNV_OFFSET
    for value in values:
        hash_value = fnv_unsigned_long(hash_value, value) if unsigned else fnv_long(hash_value, value)
    return hash_value


def default_source():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)
    return os.path.join(repo_root, "..", "doom-original", "linuxdoom-1.10", "tables.c")


def write_fixture(output_path, focal, pre, post, inverse, kind, clip):
    forward_hash = hash_array(post)
    pre_hash = hash_array(pre)
    inverse_hash = hash_array(inverse, unsigned=True)

    lines = []
    lines.append("; -----------------------------------------------------------------------------")
    lines.append("; DoomPB - independent M3-04 classic projection golden fixture (generated)")
    lines.append("; Copyright (C) 2026 DoomPB contributors")
    lines.append("; SPDX-License-Identifier: GPL-2.0-only")
    lines.append(";")
    lines.append("; Provenance: scripts/gen_projection_golden.py reads the pinned")
    lines.append("; ../doom-original/linuxdoom-1.10/tables.c (commit")
    lines.append("; a77dfb96cb91780ca334d0d4cfd86957558007e0) and uses a separate")
    lines.append("; pure-integer Python oracle for r_main.c R_InitTextureMapping.")
    lines.append("; Numeric tables/hashes only; no WAD data, graphics or copyrighted")
    lines.append("; resource payload. Do not hand-edit; regenerate deterministically.")
    lines.append("; -----------------------------------------------------------------------------")
    lines.append("")
    lines.append("CompilerIf Defined(DOOMPB_PROJGOLD_PBI, #PB_Constant) = 0")
    lines.append("")
    lines.append("#DOOMPB_PROJGOLD_PBI = 1")
    lines.append("")
    lines.append("#PROJGOLD_ForwardCount = 4096")
    lines.append("#PROJGOLD_PreCount = 4096")
    lines.append("#PROJGOLD_InverseCount = 321")
    lines.append("#PROJGOLD_ViewWidth = 320")
    lines.append("#PROJGOLD_ViewHeight = 200")
    lines.append("#PROJGOLD_CenterX = 160")
    lines.append("#PROJGOLD_CenterY = 100")
    lines.append("#PROJGOLD_CenterXFixed = 10485760")
    lines.append("#PROJGOLD_CenterYFixed = 6553600")
    lines.append("#PROJGOLD_ProjectionFixed = 10485760")
    lines.append("#PROJGOLD_FieldOfView = 2048")
    lines.append("#PROJGOLD_FocalTangentIndex = 3072")
    lines.append("")
    lines.append("DataSection")
    lines.append("  ProjectionGoldFocalLength:")
    lines.append("  Data.l %d" % focal)
    lines.append("  ProjectionGoldClipAngle:")
    lines.append("  Data.q $%08X" % clip)
    lines.append("  ProjectionGoldForwardHash:")
    lines.append("  Data.q $%016X" % forward_hash)
    lines.append("  ProjectionGoldPreHash:")
    lines.append("  Data.q $%016X" % pre_hash)
    lines.append("  ProjectionGoldInverseHash:")
    lines.append("  Data.q $%016X" % inverse_hash)

    lines.append("  ProjectionGoldThresholdKind:")
    for chunk_start in range(0, len(kind), 48):
        lines.append("  Data.b " + ",".join(str(value) for value in kind[chunk_start:chunk_start + 48]))

    lines.append("  ProjectionGoldForward:")
    for chunk_start in range(0, len(post), 16):
        lines.append("  Data.l " + ",".join(str(value) for value in post[chunk_start:chunk_start + 16]))

    lines.append("  ProjectionGoldPre:")
    for chunk_start in range(0, len(pre), 16):
        lines.append("  Data.l " + ",".join(str(value) for value in pre[chunk_start:chunk_start + 16]))

    lines.append("  ProjectionGoldInverse:")
    for chunk_start in range(0, len(inverse), 16):
        lines.append("  Data.q " + ",".join(str(value) for value in inverse[chunk_start:chunk_start + 16]))

    lines.append("EndDataSection")
    lines.append("")
    lines.append("CompilerEndIf")
    lines.append("")

    with open(output_path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines))


def main():
    parser = argparse.ArgumentParser(description="Generate DoomPB M3-04 independent projection golden fixture")
    parser.add_argument("--source", default=default_source(), help="path to pinned tables.c")
    parser.add_argument("--output", default="", help="output .pbi path (default: tests/fixtures)")
    args = parser.parse_args()

    tangent = load_tangent(args.source)
    focal, pre, post, inverse, kind, clip = build_projection(tangent)
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)
    output = args.output
    if not output:
        output = os.path.join(repo_root, "tests", "fixtures", "m3_projection_golden.pbi")
    write_fixture(output, focal, pre, post, inverse, kind, clip)
    print("fixture: %s" % output)
    print("focal %d, clipangle 0x%08X" % (focal, clip))
    print("forward hash 0x%016X, pre hash 0x%016X, inverse hash 0x%016X" % (
        hash_array(post), hash_array(pre), hash_array(inverse, unsigned=True)))


if __name__ == "__main__":
    main()
