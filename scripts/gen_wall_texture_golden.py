#!/usr/bin/env python3
# -----------------------------------------------------------------------------
# DoomPB - independent M3-06 textured wall/COLORMAP lighting fixture generator
# Copyright (C) 2026 DoomPB contributors
# SPDX-License-Identifier: GPL-2.0-only
#
"""
DoomPB - independent M3-06 textured wall-column/lighting golden generator.

Provenance and independence: geometry, projection, BSP/visibility and M3-05 plan
formulas are computed by the already published independent Python oracle
gen_wall_projection_golden.py, which reads only numeric trig tables from the
pinned ../doom-original/linuxdoom-1.10/tables.c (commit
a77dfb96cb91780ca334d0d4cfd86957558007e0). This script adds separate integer
oracles for the M3-06 material selection, r_segs.c rw_offset/rw_centerangle,
r_draw.c dc_iscale/frac/source_row, r_data.c width mask, and r_main.c/r_segs.c
scalelight[16][48] COLORMAP lighting. It composes only the small original
synthetic resources encoded below (PARTA/PARTB/PARTUP/PARTLO, 32 COLORMAP tables)
and renders the two synthetic TI01/TI02 scenes.

Never from production output: expected spans, plans, full 64,000-byte synthetic
frames, FNV-1a64 hashes, sample rows, independent M3-04 span fingerprints,
component counters and helper scalars come from this Python oracle. No commercial
WAD bytes, Doom graphics, copyrighted resource payload or screenshots are stored
or emitted. The fixture is totally
synthetic numeric/pixel data and deterministic; do not hand-edit. Regeneration
twice must produce byte-identical content.

Production and tests never execute Python.
"""
import argparse
import importlib.util
import os
import sys

MASK32 = 0xFFFFFFFF
SIGN32 = 0x80000000
SHORT_MIN = -32768
SHORT_MAX = 32767
FRACBITS = 16
FRACUNIT = 1 << FRACBITS
FINEANGLES = 8192
ANGLETOFINESHIFT = 19
ANG90 = 0x40000000
ANG180 = 0x80000000
VIEWWIDTH = 320
VIEWHEIGHT = 200
CENTERY = 100
HEIGHTBITS = 12
HEIGHTUNIT = 1 << HEIGHTBITS
MAP_ML_DONTPEGTOP = 8
MAP_ML_DONTPEGBOTTOM = 16
LIGHT_LEVELS = 16
LIGHT_SEGSHIFT = 4
LIGHT_MAXLIGHTSCALE = 48
LIGHT_SCALESHIFT = 12
LIGHT_NUMCOLORMAPS = 32
LIGHT_DISTMAP = 2
LIGHT_SCREENWIDTH = VIEWWIDTH
LIGHT_DETAILSHIFT = 0
MAXDRAWSIZE = 4096
FNV_OFFSET = 14695981039346656037
FNV_PRIME = 1099511628211

SYNTH_PATCH_A = 37
SYNTH_PATCH_B = 201
SYNTH_PATCH_UP = 73
SYNTH_PATCH_LO = 19
SYNTH_COLORMAP_BASE = 17
SYNTH_COLORMAP_STEP = 9

NO_TEXTURE = -1
NO_CACHE_SLOT = -1


def unsigned32(value):
    return value & MASK32


def signed32(value):
    low = value & MASK32
    if low >= SIGN32:
        return low - (1 << 32)
    return low


def lowadd(a, b):
    return signed32(unsigned32(a) + unsigned32(b))


def lowsub(a, b):
    return signed32(unsigned32(a) - unsigned32(b))


def lowneg(a):
    return signed32(-unsigned32(a))


def fixed_mul(a, b):
    return signed32(signed32(a) * signed32(b) >> FRACBITS)


def trunc_div(numerator, denominator):
    if numerator == 0:
        return 0
    magnitude = abs(numerator) // abs(denominator)
    if (numerator < 0) != (denominator < 0):
        return -magnitude
    return magnitude


def load_base_oracle():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    module_path = os.path.join(script_dir, "gen_wall_projection_golden.py")
    spec = importlib.util.spec_from_file_location("wall_projection_oracle",
                                                  module_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def seg_raw_to_bam(raw16):
    return unsigned32((unsigned32(raw16) & 0xFFFF) << FRACBITS)


# -----------------------------------------------------------------------------
# Synthetic resource material (bounded original stand-ins, no IWAD bytes)
# -----------------------------------------------------------------------------

TEXTURE_DEFS = [
    {"name": "NODEF", "width": 8, "height": 128, "kind": "A"},
    {"name": "TEXMID", "width": 64, "height": 128, "kind": "MID"},
    {"name": "TEXUP", "width": 96, "height": 72, "kind": "UP"},
    {"name": "TEXLO", "width": 64, "height": 64, "kind": "LO"},
    {"name": "TEXEXTRA", "width": 64, "height": 128, "kind": "A"},
]

PAMES = ["PARTA", "PARTB", "PARTUP", "PARTLO"]


def slot_name_bytes(name):
    """Canonical eight-byte wall slot comparison: "-", empty and all-NUL are absent."""
    if name is None:
        return 0
    if name == "" or name == "-":
        return 0
    return 0 if any(ord(ch) == 0 for ch in name) else 1


def catalog_find_name(name):
    """First-match catalog binding; catalog index 0 equals the NO_TEXTURE quirk."""
    if slot_name_bytes(name) == 0:
        return {"present": 0, "index": NO_TEXTURE}
    for index, definition in enumerate(TEXTURE_DEFS):
        if definition["name"].lower() == name.lower():
            if index == 0:
                return {"present": 0, "index": NO_TEXTURE}
            return {"present": 1, "index": index}
    return None


def texture_width_mask(width):
    power = 1
    while power * 2 <= width:
        power <<= 1
    return power - 1


def texture_height_fixed(height):
    return signed32(height << FRACBITS)


def texture_image(index):
    definition = TEXTURE_DEFS[index]
    width = definition["width"]
    height = definition["height"]
    pixels = [0] * (width * height)
    mask = [0] * (width * height)
    for y in range(height):
        for x in range(width):
            if definition["kind"] == "MID":
                colour = SYNTH_PATCH_A if x < 32 else SYNTH_PATCH_B
            elif definition["kind"] == "UP":
                colour = SYNTH_PATCH_UP
            elif definition["kind"] == "LO":
                colour = SYNTH_PATCH_LO
            else:
                colour = SYNTH_PATCH_A
            pixels[y * width + x] = colour
            mask[y * width + x] = 1
    return {
        "index": index,
        "width": width,
        "height": height,
        "mask": texture_width_mask(width),
        "short": 1 if height < 128 else 0,
        "pixels": pixels,
        "maskbytes": mask,
    }


COLORMAP_TABLES = []
for map_index in range(LIGHT_NUMCOLORMAPS):
    table = [0] * 256
    for texel in range(256):
        table[texel] = (texel + SYNTH_COLORMAP_BASE + map_index * SYNTH_COLORMAP_STEP) & 255
    COLORMAP_TABLES.append(table)


def scalelight_table():
    """r_main.c R_ExecuteSetViewSize canonical 16x48 startmap/level clamp."""
    table = [[0] * LIGHT_MAXLIGHTSCALE for _ in range(LIGHT_LEVELS)]
    for light_level in range(LIGHT_LEVELS):
        startmap = ((LIGHT_LEVELS - 1 - light_level) * 2) * LIGHT_NUMCOLORMAPS // LIGHT_LEVELS
        if startmap < 0 or startmap > (LIGHT_LEVELS - 1) * 2 * LIGHT_NUMCOLORMAPS // LIGHT_LEVELS:
            raise ValueError("scalelight startmap outside source domain")
        for scale_index in range(LIGHT_MAXLIGHTSCALE):
            step = scale_index * LIGHT_SCREENWIDTH // \
                (VIEWWIDTH << LIGHT_DETAILSHIFT) // LIGHT_DISTMAP
            level = startmap - step
            if level < 0:
                level = 0
            elif level >= LIGHT_NUMCOLORMAPS:
                level = 31
            table[light_level][scale_index] = level
    return table


SCALELIGHT = scalelight_table()


def light_row(front_light, v1x, v1y, v2x, v2y):
    shifted = front_light >> LIGHT_SEGSHIFT
    if v1y == v2y:
        shifted -= 1
    elif v1x == v2x:
        shifted += 1
    if shifted < 0:
        shifted = 0
    elif shifted >= LIGHT_LEVELS:
        shifted = 15
    return shifted


def scale_index(scale):
    index = scale >> LIGHT_SCALESHIFT
    if index >= LIGHT_MAXLIGHTSCALE:
        index = LIGHT_MAXLIGHTSCALE - 1
    return index


def iscale_value(scale):
    return 0xFFFFFFFF // scale


def colormap_mapped_value(texel, light_level, column_index):
    map_index = SCALELIGHT[light_level][column_index]
    return COLORMAP_TABLES[map_index][texel]


# -----------------------------------------------------------------------------
# TI01 / TI02 synthetic scene definitions (mirrored by wall_texture_support.pbi)
# -----------------------------------------------------------------------------

COMMON_SECTOR = {
    "floor": 0, "ceiling": 128, "light": 160,
    "floorpic": "FLOOR1", "ceilingpic": "CEIL1",
}

TI01_SCENE = {
    "sectors": [COMMON_SECTOR],
    "lines": [{"v1": 0, "v2": 1, "flags": 0, "side0": 0, "side1": -1}],
    "sides": [{
        "sector": 0, "top": "-", "bottom": "-", "mid": "TEXMID",
        "textureoffset": 5, "rowoffset": -3,
    }],
    "verts": [(100, 64), (100, -64)],
    "segs": [{"v1": 0, "v2": 1, "raw16": 49152, "line": 0, "side": 0,
              "offset": -7}],
    "subs": [{"first": 0, "num": 1}],
    "nodes": [],
    "view": (0, 0, 0, 41 << FRACBITS),
    "samples": [0, 100, 159, 160, 161, 319],
}

TI02_SCENE = {
    "sectors": [
        {"floor": 0, "ceiling": 128, "light": 160,
         "floorpic": "FLOOR1", "ceilingpic": "CEIL1"},
        {"floor": 32, "ceiling": 96, "light": 96,
         "floorpic": "FLOOR2", "ceilingpic": "CEIL2"},
    ],
    "lines": [
        {"v1": 0, "v2": 1, "flags": 0, "side0": 0, "side1": -1},
        {"v1": 2, "v2": 3, "flags": 4 + MAP_ML_DONTPEGTOP, "side0": 1, "side1": 2},
        {"v1": 4, "v2": 5, "flags": 4, "side0": 3, "side1": 4},
    ],
    "sides": [
        {"sector": 0, "top": "-", "bottom": "-", "mid": "TEXMID",
         "textureoffset": 0, "rowoffset": 0},
        {"sector": 0, "top": "TEXUP", "bottom": "TEXLO", "mid": "TEXMID",
         "textureoffset": 11, "rowoffset": -8},
        {"sector": 1, "top": "-", "bottom": "-", "mid": "-",
         "textureoffset": 0, "rowoffset": 0},
        {"sector": 0, "top": "TEXUP", "bottom": "TEXLO", "mid": "-",
         "textureoffset": 3, "rowoffset": 5},
        {"sector": 1, "top": "TEXLO", "bottom": "TEXUP", "mid": "-",
         "textureoffset": 0, "rowoffset": 0},
    ],
    "verts": [(100, 64), (100, -64), (300, 32767), (300, -32767),
              (200, 240), (300, 240), (80, -200), (160, -320)],
    "segs": [
        {"v1": 0, "v2": 1, "raw16": 49152, "line": 0, "side": 0, "offset": 0},
        {"v1": 2, "v2": 3, "raw16": 49152, "line": 1, "side": 0, "offset": 4},
        {"v1": 4, "v2": 5, "raw16": 0, "line": 2, "side": 0, "offset": 2},
    ],
    "subs": [{"first": 0, "num": 3}],
    "nodes": [],
    "view": (0, 0, 0, 41 << FRACBITS),
    "samples": [0, 58, 120, 160, 200, 240, 300, 319],
}


def sidedef_for_span(scene, span):
    line = scene["lines"][span["line"]]
    side_index = line["side0"] if span["side"] == 0 else line["side1"]
    if side_index < 0:
        raise ValueError("span selects absent sidedef")
    return side_index, scene["sides"][side_index]


def texture_offset_and_center(scene, span, plan):
    """r_segs.c R_StoreWallRange offsetangle branch, exact unsigned/sign/clamp order."""
    seg = span["seg_data"]
    v1 = scene["verts"][seg["v1"]]
    normal = unsigned32(plan["NormalAngle"])
    reference = unsigned32(plan["ReferenceAngle"])
    raw_delta = unsigned32(normal - reference)
    offset_angle = raw_delta
    if offset_angle > ANG180:
        offset_angle = unsigned32(-offset_angle)
    if offset_angle > ANG90:
        offset_angle = ANG90
    fine_index = offset_angle >> ANGLETOFINESHIFT
    if fine_index < 0 or fine_index > 4095:
        raise ValueError("texture offset finesine index outside table")
    sine = scene["sine"][fine_index]
    product = fixed_mul(plan["Hyp"], sine)
    if raw_delta < ANG180:
        product = lowneg(product)

    _, sidedef = sidedef_for_span(scene, span)
    texture_offset_fixed = signed32(sidedef["textureoffset"] << FRACBITS)
    seg_offset_fixed = signed32(seg["offset"] << FRACBITS)
    rw_offset = lowadd(lowadd(product, texture_offset_fixed), seg_offset_fixed)
    center = unsigned32(ANG90 + unsigned32(scene["view"][2]) - normal)
    return rw_offset, center, sidedef, v1


def texture_mid_one_sided(sidedef, line, front, plan):
    height_fixed = texture_height_fixed(TEXTURE_DEFS[1]["height"])
    worldtop_raw = signed32(plan["WorldTopRaw"])
    row_fixed = signed32(sidedef["rowoffset"] << FRACBITS)
    if line["flags"] & MAP_ML_DONTPEGBOTTOM:
        vtop = lowadd(signed32(front["floor"] << FRACBITS), height_fixed)
        mid = lowsub(vtop, signed32(plan["ViewZ"]))
    else:
        mid = worldtop_raw
    return lowadd(mid, row_fixed)


def texture_mid_upper(scene, span, sidedef, line, plan):
    bound = catalog_find_name(sidedef["top"])
    if bound is None or bound["present"] == 0:
        raise ValueError("upper tier absent")
    index = bound["index"]
    definition = TEXTURE_DEFS[index]
    height_fixed = texture_height_fixed(definition["height"])
    row_fixed = signed32(sidedef["rowoffset"] << FRACBITS)
    if line["flags"] & MAP_ML_DONTPEGTOP:
        mid = signed32(plan["WorldTopRaw"])
    else:
        back_ceil_fixed = signed32(scene["sectors"][span["back"]]["ceiling"] << FRACBITS)
        vtop = lowadd(back_ceil_fixed, height_fixed)
        mid = lowsub(vtop, signed32(plan["ViewZ"]))
    return lowadd(mid, row_fixed)


def texture_mid_lower(scene, span, sidedef, line, plan):
    bound = catalog_find_name(sidedef["bottom"])
    if bound is None or bound["present"] == 0:
        raise ValueError("lower tier absent")
    index = bound["index"]
    row_fixed = signed32(sidedef["rowoffset"] << FRACBITS)
    if line["flags"] & MAP_ML_DONTPEGBOTTOM:
        mid = signed32(plan["WorldTopRaw"])
    else:
        mid = signed32(plan["WorldLowRaw"])
    return lowadd(mid, row_fixed)


def add_viewz_key(scene, plan):
    """The base oracle plan omits explicit viewz; add the exact scene view value."""
    plan["ViewZ"] = scene["view"][3]


def textured_plan(scene, span, plan):
    plan = dict(plan)
    add_viewz_key(scene, plan)
    _, sidedef = sidedef_for_span(scene, span)
    line = scene["lines"][span["line"]]
    front = scene["sectors"][span["front"]]
    seg = span["seg_data"]

    mid_index = top_index = bottom_index = masked_index = NO_TEXTURE
    mid_height = top_height = bottom_height = 0
    mid_mid = top_mid = bottom_mid = 0
    mid_width = top_width = bottom_width = 0
    mid_mask = top_mask = bottom_mask = 0
    has_painted = 0
    segment_textured = 0
    masked_mid = 0
    raw_offset = 0
    center = 0
    light = 0

    if plan["MiddleTier"]:
        bound = catalog_find_name(sidedef["mid"])
        if bound is None or bound["present"] == 0:
            raise ValueError("one-sided middle tier with absent name")
        mid_index = bound["index"]
        definition = TEXTURE_DEFS[mid_index]
        mid_width, mid_height = definition["width"], definition["height"]
        mid_mask = texture_width_mask(mid_width)
        mid_mid = texture_mid_one_sided(sidedef, line, front, plan)

    if plan["TopTier"]:
        bound = catalog_find_name(sidedef["top"])
        if bound is None or bound["present"] == 0:
            raise ValueError("upper tier with absent name")
        top_index = bound["index"]
        definition = TEXTURE_DEFS[top_index]
        top_width, top_height = definition["width"], definition["height"]
        top_mask = texture_width_mask(top_width)
        top_mid = texture_mid_upper(scene, span, sidedef, line, plan)

    if plan["BottomTier"]:
        bound = catalog_find_name(sidedef["bottom"])
        if bound is None or bound["present"] == 0:
            raise ValueError("lower tier with absent name")
        bottom_index = bound["index"]
        definition = TEXTURE_DEFS[bottom_index]
        bottom_width, bottom_height = definition["width"], definition["height"]
        bottom_mask = texture_width_mask(bottom_width)
        bottom_mid = texture_mid_lower(scene, span, sidedef, line, plan)

    if plan["BackSector"] >= 0:
        bound = catalog_find_name(sidedef["mid"])
        if bound is None:
            raise ValueError("masked mid field unresolved")
        masked_index = bound["index"]
        if bound["present"]:
            masked_mid = 1

    if mid_height > 0 or top_height > 0 or bottom_height > 0 or masked_mid:
        segment_textured = 1
        raw_offset, center, _, _1 = texture_offset_and_center(scene, span, plan)
        v1 = scene["verts"][seg["v1"]]
        v2 = scene["verts"][seg["v2"]]
        light = light_row(front["light"], v1[0], v1[1], v2[0], v2[1])
    if mid_height > 0 or top_height > 0 or bottom_height > 0:
        has_painted = 1

    plan.update({
        "MidTextureIndex": mid_index, "TopTextureIndex": top_index,
        "BottomTextureIndex": bottom_index, "MaskedMidIndex": masked_index,
        "MidTextureMid": mid_mid, "TopTextureMid": top_mid,
        "BottomTextureMid": bottom_mid,
        "MidWidth": mid_width, "MidHeight": mid_height, "MidWidthMask": mid_mask,
        "TopWidth": top_width, "TopHeight": top_height, "TopWidthMask": top_mask,
        "BottomWidth": bottom_width, "BottomHeight": bottom_height,
        "BottomWidthMask": bottom_mask,
        "RawOffset": raw_offset, "CenterAngle": center, "LightNum": light,
        "MaskedMid": masked_mid, "HasPaintedTier": has_painted,
        "SegmentTextured": segment_textured,
        "FrontLight": front["light"],
        "TwoSided": 1 if span["back"] >= 0 else 0,
    })
    return plan


L_TEXTURE_PLAN_FIELDS = [
    "Subsector", "Seg", "Linedef", "Side", "FrontSector", "BackSector",
    "FirstX", "LastX", "Kind",
    "Scale1", "Scale2", "ScaleStep", "Hyp", "Distance",
    "WorldTopRaw", "WorldBottomRaw", "WorldHighRaw", "WorldLowRaw",
    "WorldTop", "WorldBottom", "WorldHigh", "WorldLow",
    "TopFrac", "BottomFrac", "TopStep", "BottomStep",
    "PixHigh", "PixLow", "PixHighStep", "PixLowStep",
    "MarkFloor", "MarkCeiling", "TopRegion", "BottomRegion",
    "TopTier", "BottomTier", "MiddleTier", "TwoSided",
    "FrontLight", "ClosedDoor", "SkyHack",
    "MidTextureIndex", "TopTextureIndex", "BottomTextureIndex", "MaskedMidIndex",
    "MidTextureMid", "TopTextureMid", "BottomTextureMid",
    "MidWidth", "MidHeight", "MidWidthMask",
    "TopWidth", "TopHeight", "TopWidthMask",
    "BottomWidth", "BottomHeight", "BottomWidthMask",
    "RawOffset", "LightNum", "MaskedMid", "HasPaintedTier", "SegmentTextured",
]
Q_TEXTURE_PLAN_FIELDS = [
    "ViewAngle", "NormalAngle", "ReferenceAngle", "OffsetAngle", "DistAngle",
    "CenterAngle",
]


def compose_cache(scene, plans):
    """Chronological painted-tier reference collection, excluding deferred masked middles."""
    slots = {}
    unique = []
    requested = 0
    reused = 0
    masked_mid_spans = 0
    for plan in plans:
        if plan["TopTier"]:
            requested += 1
            index = plan["TopTextureIndex"]
            if index in slots:
                reused += 1
            else:
                slots[index] = len(unique)
                unique.append(index)
        if plan["BottomTier"]:
            requested += 1
            index = plan["BottomTextureIndex"]
            if index in slots:
                reused += 1
            else:
                slots[index] = len(unique)
                unique.append(index)
        if plan["MiddleTier"]:
            requested += 1
            index = plan["MidTextureIndex"]
            if index in slots:
                reused += 1
            else:
                slots[index] = len(unique)
                unique.append(index)
        if plan["BackSector"] >= 0:
            line = scene["lines"][plan["Linedef"]]
            side_index = line["side0"] if plan["Side"] == 0 else line["side1"]
            if side_index < 0:
                raise ValueError("cache masked mid selects absent sidedef")
            bound = catalog_find_name(scene["sides"][side_index]["mid"])
            if bound is None:
                raise ValueError("cache masked mid unresolved")
            if bound["present"]:
                masked_mid_spans += 1
    short_textures = sum(1 for index in unique if TEXTURE_DEFS[index]["height"] < 128)
    cache_allocations = 1 + (1 if unique else 0) + 2 * len(unique)
    return {
        "slots": slots,
        "unique": unique,
        "composed": len(unique),
        "requested": requested,
        "reused": reused,
        "masked": masked_mid_spans,
        "short": short_textures,
        "allocations": cache_allocations,
    }


def pixel_value(image, column, row128):
    source_row = row128 if image["height"] >= 128 else row128 % image["height"]
    fallback = 0 if image["height"] >= 128 else 1
    offset = source_row * image["width"] + column
    return (image["pixels"][offset], image["maskbytes"][offset], fallback,
            source_row)


def draw_column(frame, plan, image, texture_mid, source_column, screen_column,
                ylow, yhigh, light, column_index, counters):
    if ylow > yhigh:
        counters["empty_ranges"] += 1
        return 0
    if screen_column < 0 or screen_column > VIEWWIDTH - 1 or ylow < 0 or \
       yhigh < 0 or ylow > VIEWHEIGHT - 1 or yhigh > VIEWHEIGHT - 1:
        counters["out_of_frame"] += 1
        raise ValueError("textured range escaped screen")
    scale = plan["Scale1Current"]
    iscale = iscale_value(scale)
    frac = lowadd(texture_mid, signed32((ylow - CENTERY) * iscale))
    pixels = 0
    tier = counters["tier"]
    for row in range(ylow, yhigh + 1):
        row128 = (frac >> FRACBITS) & 127
        texel, opaque, fallback, _ = pixel_value(image, source_column, row128)
        mapped = colormap_mapped_value(texel, light, column_index)
        frame[row * VIEWWIDTH + screen_column] = mapped
        pixels += 1
        counters["samples"] += 1
        if opaque == 0:
            counters["uncovered"] += 1
        if fallback:
            counters["fallbacks"] += 1
        frac = lowadd(frac, iscale)
    counters[tier + "_pixels"] += pixels
    counters[tier + "_ranges"] += 1
    counters["drawn_ranges"] += 1
    return pixels


def texture_column(plan, column, projection, scene):
    angle_sum = unsigned32(plan["CenterAngle"] + projection["inverse"][column])
    index = angle_sum >> ANGLETOFINESHIFT
    if index < 0 or index > 4095:
        raise ValueError("texture column tangent index outside finetangent")
    tangent = scene["tangent"][index]
    fixed = lowsub(plan["RawOffset"], fixed_mul(tangent, plan["Distance"]))
    return fixed >> FRACBITS


def draw_textured_frame(scene, plans, projection, cache):
    frame = [0] * (VIEWWIDTH * VIEWHEIGHT)
    ceilingclip = [-1] * VIEWWIDTH
    floorclip = [VIEWHEIGHT] * VIEWWIDTH
    counters = {
        "processed_columns": 0, "texture_columns": 0,
        "middle_pixels": 0, "upper_pixels": 0, "lower_pixels": 0,
        "middle_ranges": 0, "upper_ranges": 0, "lower_ranges": 0,
        "drawn_ranges": 0, "empty_columns": 0, "clipped_columns": 0,
        "out_of_frame": 0, "samples": 0, "uncovered": 0, "fallbacks": 0,
        "empty_ranges": 0,
    }
    images = {index: texture_image(index) for index in cache["unique"]}
    for plan in plans:
        scale = plan["Scale1"]
        topfrac = plan["TopFrac"]
        bottomfrac = plan["BottomFrac"]
        pixhigh = plan["PixHigh"]
        pixlow = plan["PixLow"]
        for column in range(plan["FirstX"], plan["LastX"] + 1):
            plan["Scale1Current"] = scale
            counters["processed_columns"] += 1
            ceilclip = ceilingclip[column]
            floorclip_current = floorclip[column]
            drew = 0
            clipped = 0
            yl = lowadd(topfrac, HEIGHTUNIT - 1) >> HEIGHTBITS
            if yl < ceilclip + 1:
                yl = ceilclip + 1
                clipped = 1
            yh = bottomfrac >> HEIGHTBITS
            if yh >= floorclip_current:
                yh = floorclip_current - 1
                clipped = 1

            column_index = 0
            raw_column = 0
            computed = 0
            if plan["SegmentTextured"]:
                raw_column = texture_column(plan, column, projection, scene)
                column_index = scale_index(scale)
                computed = 1
                counters["texture_columns"] += 1

            if plan["MiddleTier"]:
                image = images[plan["MidTextureIndex"]]
                wrapped = raw_column & plan["MidWidthMask"]
                counters["tier"] = "middle"
                drawn_pixels = draw_column(frame, plan, image,
                                           plan["MidTextureMid"],
                                           wrapped, column,
                                           yl, yh, plan["LightNum"],
                                           column_index, counters)
                if drawn_pixels:
                    drew = 1
                ceilingclip[column] = VIEWHEIGHT
                floorclip[column] = -1
            else:
                if plan["TopTier"]:
                    mid = pixhigh >> HEIGHTBITS
                    pixhigh = lowadd(pixhigh, plan["PixHighStep"])
                    if mid >= floorclip_current:
                        mid = floorclip_current - 1
                        clipped = 1
                    if mid >= yl:
                        image = images[plan["TopTextureIndex"]]
                        wrapped = raw_column & plan["TopWidthMask"]
                        counters["tier"] = "upper"
                        pixels = draw_column(frame, plan, image,
                                             plan["TopTextureMid"],
                                             wrapped, column,
                                             yl, mid, plan["LightNum"],
                                             column_index, counters)
                        if pixels:
                            drew = 1
                        ceilingclip[column] = mid
                    else:
                        ceilingclip[column] = yl - 1
                elif plan["MarkCeiling"]:
                    ceilingclip[column] = yl - 1

                if plan["BottomTier"]:
                    mid = lowadd(pixlow, HEIGHTUNIT - 1) >> HEIGHTBITS
                    pixlow = lowadd(pixlow, plan["PixLowStep"])
                    if mid <= ceilclip:
                        mid = ceilclip + 1
                        clipped = 1
                    if mid <= yh:
                        image = images[plan["BottomTextureIndex"]]
                        wrapped = raw_column & plan["BottomWidthMask"]
                        counters["tier"] = "lower"
                        pixels = draw_column(frame, plan, image,
                                             plan["BottomTextureMid"],
                                             wrapped, column,
                                             mid, yh, plan["LightNum"],
                                             column_index, counters)
                        if pixels:
                            drew = 1
                        floorclip[column] = mid
                    else:
                        floorclip[column] = yh + 1
                elif plan["MarkFloor"]:
                    floorclip[column] = yh + 1

            if clipped:
                counters["clipped_columns"] += 1
            if not drew:
                counters["empty_columns"] += 1
            scale = lowadd(scale, plan["ScaleStep"])
            topfrac = lowadd(topfrac, plan["TopStep"])
            bottomfrac = lowadd(bottomfrac, plan["BottomStep"])
    counters["drawn_pixels"] = counters["middle_pixels"] + \
        counters["upper_pixels"] + counters["lower_pixels"]
    return frame, counters


def frame_hash(frame):
    value = FNV_OFFSET
    for byte in frame:
        value = ((value ^ (byte & 255)) * FNV_PRIME) & 0xFFFFFFFFFFFFFFFF
    return value


def span_hash(spans):
    """FNV-1a64 over the M3-04 nine-int span vector, in published chronology.

    Mirrors the aggregate WallVisibility fingerprint (little-endian .l bytes,
    SOLID=0/PASS=1) from the independent span records; no production hash read.
    """
    value = FNV_OFFSET
    for span in spans:
        for field in (span["sub"], span["seg"], span["line"], span["side"],
                      span["front"], span["back"], span["first"], span["last"],
                      0 if span["kind"] == "SOLID" else 1):
            field = unsigned32(field)
            for shift in (0, 8, 16, 24):
                value = ((value ^ ((field >> shift) & 255)) * FNV_PRIME) & 0xFFFFFFFFFFFFFFFF
    return value


def build_scene(scene, tables, base):
    tangent, sine, tant = tables
    focal, pre, post, inverse, kind, clip = base.build_projection(tangent)
    projection = {"focal": focal, "post": post, "inverse": inverse, "clip": clip}
    scene = dict(scene)
    scene["tant"] = tant
    scene["sine"] = sine
    scene["tangent"] = tangent
    spans = base.visible_spans(scene, projection)
    plans = [base.span_plan(scene, span, projection, sine, tant) for span in spans]
    for index, plan in enumerate(plans):
        plan["ViewZ"] = scene["view"][3]
        plans[index] = textured_plan(scene, spans[index], plan)
    cache = compose_cache(scene, plans)
    frame, counters = draw_textured_frame(scene, plans, projection, cache)
    nonzero = sum(1 for byte in frame if byte != 0)
    zero = len(frame) - nonzero
    samples = []
    for x in scene["samples"]:
        samples.append([frame[row * VIEWWIDTH + x] for row in range(VIEWHEIGHT)])
    allocation_total = 5 + cache["allocations"]
    return {
        "scene": scene,
        "spans": spans,
        "plans": plans,
        "cache": cache,
        "frame": frame,
        "counters": counters,
        "nonzero": nonzero,
        "zero": zero,
        "hash": frame_hash(frame),
        "span_hash": span_hash(spans),
        "samples": samples,
        "allocations": allocation_total,
    }


# -----------------------------------------------------------------------------
# Fixture emission
# -----------------------------------------------------------------------------

def flat_l(plan_list, fields):
    values = []
    for plan in plan_list:
        for field in fields:
            values.append(plan[field])
    return values


def flat_q(plan_list, fields):
    values = []
    for plan in plan_list:
        for field in fields:
            values.append(unsigned32(plan[field]))
    return values


def emit_ints(lines, label, values, stride=16):
    lines.append("  %s:" % label)
    for start in range(0, len(values), stride):
        lines.append("  Data.l " + ",".join(str(v) for v in values[start:start + stride]))


def emit_bytes(lines, label, values, stride=32):
    lines.append("  %s:" % label)
    for start in range(0, len(values), stride):
        lines.append("  Data.b " + ",".join(str(v) for v in values[start:start + stride]))


def emit_quads(lines, label, values, stride=8):
    lines.append("  %s:" % label)
    for start in range(0, len(values), stride):
        lines.append("  Data.q " + ",".join("$%08X" % unsigned32(v) for v in values[start:start + stride]))


def write_fixture(output_path, built):
    lines = []
    add = lines.append
    add("; -----------------------------------------------------------------------------")
    add("; DoomPB - independent M3-06 textured wall/COLORMAP golden fixture (generated)")
    add("; Copyright (C) 2026 DoomPB contributors")
    add("; SPDX-License-Identifier: GPL-2.0-only")
    add(";")
    add("; Provenance: scripts/gen_wall_texture_golden.py reuses the published")
    add("; independent Python geometry oracle gen_wall_projection_golden.py (pinned")
    add("; tables.c commit a77dfb96cb91780ca334d0d4cfd86957558007e0) and adds")
    add("; separate integer oracles for material selection, rw_offset, width mask,")
    add("; dc_iscale/frac/&127 safe row policy and scalelight/COLORMAP mapping on")
    add("; wholly original synthetic resources TI01/TI02. Full 64,000-byte synthetic")
    add("; TI01/TI02 frames, FNV hashes, independent M3-04 span fingerprints, sample")
    add("; rows, span/plan vectors, counters and helper scalars only; no WAD,")
    add("; commercial graphics or copyrighted payload.")
    add("; Do not hand-edit; regenerate deterministically.")
    add("; -----------------------------------------------------------------------------")
    add("")
    add("CompilerIf Defined(DOOMPB_WALLTEXGOLD_PBI, #PB_Constant) = 0")
    add("")
    add("#DOOMPB_WALLTEXGOLD_PBI = 1")
    add("")
    add("#TEXGOLD_ViewWidth = 320")
    add("#TEXGOLD_ViewHeight = 200")
    add("#TEXGOLD_PixelCount = 64000")
    add("#TEXGOLD_SpanFieldCount = 9")
    add("#TEXGOLD_PlanLFieldCount = %d" % len(L_TEXTURE_PLAN_FIELDS))
    add("#TEXGOLD_PlanQFieldCount = %d" % len(Q_TEXTURE_PLAN_FIELDS))
    add("#TEXGOLD_SampleRowBytes = 200")
    add("#TEXGOLD_FNV_Offset = -3750763034362895579")
    add("#TEXGOLD_FNV_Prime = 1099511628211")
    add("#TEXGOLD_WidthMask64_Value = %d" % texture_width_mask(64))
    add("#TEXGOLD_WidthMask96_Value = %d" % texture_width_mask(96))
    add("#TEXGOLD_WidthMask128_Value = %d" % texture_width_mask(128))
    add("#TEXGOLD_WidthMask256_Value = %d" % texture_width_mask(256))
    add("#TEXGOLD_Iscale256_Value = %d" % iscale_value(256))
    add("#TEXGOLD_Iscale512_Value = %d" % iscale_value(512))
    add("#TEXGOLD_Iscale2_Value = %d" % iscale_value(2))
    add("#TEXGOLD_ScalelightBinCount = %d" % (LIGHT_LEVELS * LIGHT_MAXLIGHTSCALE))
    add("#TEXGOLD_ScalelightMapLevelCount = %d" % LIGHT_NUMCOLORMAPS)
    add("#TEXGOLD_PatchA = %d" % SYNTH_PATCH_A)
    add("#TEXGOLD_PatchB = %d" % SYNTH_PATCH_B)
    add("#TEXGOLD_PatchUp = %d" % SYNTH_PATCH_UP)
    add("#TEXGOLD_PatchLo = %d" % SYNTH_PATCH_LO)
    add("#TEXGOLD_ColormapBase = %d" % SYNTH_COLORMAP_BASE)
    add("#TEXGOLD_ColormapStep = %d" % SYNTH_COLORMAP_STEP)
    add("#TEXGOLD_TEXTURE_Count = %d" % len(TEXTURE_DEFS))
    add("#TEXGOLD_SourceRow32_127 = %d" % (127 % 32))
    add("#TEXGOLD_SourceRow64_127 = %d" % (127 % 64))
    add("#TEXGOLD_SourceRow72_127 = %d" % (127 % 72))
    add("#TEXGOLD_SourceRow128_127 = 127")
    add("#TEXGOLD_SourceRow256_127 = 127")

    for name in ("TI01", "TI02"):
        data = built[name]
        add("#TEXGOLD_%s_SpanCount = %d" % (name, len(data["spans"])))
        add("#TEXGOLD_%s_SpanHash = $%016X" % (name, data["span_hash"]))
        add("#TEXGOLD_%s_Composed = %d" % (name, data["cache"]["composed"]))
        add("#TEXGOLD_%s_Requested = %d" % (name, data["cache"]["requested"]))
        add("#TEXGOLD_%s_Reused = %d" % (name, data["cache"]["reused"]))
        add("#TEXGOLD_%s_MaskedMidSpans = %d" % (name, data["cache"]["masked"]))
        add("#TEXGOLD_%s_ShortTextures = %d" % (name, data["cache"]["short"]))
        add("#TEXGOLD_%s_CacheAllocations = %d" % (name, data["cache"]["allocations"]))
        add("#TEXGOLD_%s_Allocations = %d" % (name, data["allocations"]))
        counters = data["counters"]
        add("#TEXGOLD_%s_ProcessedColumns = %d" % (name, counters["processed_columns"]))
        add("#TEXGOLD_%s_TextureColumns = %d" % (name, counters["texture_columns"]))
        add("#TEXGOLD_%s_DrawnPixels = %d" % (name, counters["drawn_pixels"]))
        add("#TEXGOLD_%s_MiddlePixels = %d" % (name, counters["middle_pixels"]))
        add("#TEXGOLD_%s_UpperPixels = %d" % (name, counters["upper_pixels"]))
        add("#TEXGOLD_%s_LowerPixels = %d" % (name, counters["lower_pixels"]))
        add("#TEXGOLD_%s_MiddleRanges = %d" % (name, counters["middle_ranges"]))
        add("#TEXGOLD_%s_UpperRanges = %d" % (name, counters["upper_ranges"]))
        add("#TEXGOLD_%s_LowerRanges = %d" % (name, counters["lower_ranges"]))
        add("#TEXGOLD_%s_DrawRanges = %d" % (name, counters["drawn_ranges"]))
        add("#TEXGOLD_%s_EmptyColumns = %d" % (name, counters["empty_columns"]))
        add("#TEXGOLD_%s_ClippedColumns = %d" % (name, counters["clipped_columns"]))
        add("#TEXGOLD_%s_OutOfFrameColumns = %d" % (name, counters["out_of_frame"]))
        add("#TEXGOLD_%s_TextureSamples = %d" % (name, counters["samples"]))
        add("#TEXGOLD_%s_UncoveredTexels = %d" % (name, counters["uncovered"]))
        add("#TEXGOLD_%s_ShortHeightFallbacks = %d" % (name, counters["fallbacks"]))
        add("#TEXGOLD_%s_NonZeroBytes = %d" % (name, data["nonzero"]))
        add("#TEXGOLD_%s_ZeroBytes = %d" % (name, data["zero"]))
        add("#TEXGOLD_%s_SampleCount = %d" % (name, len(data["samples"])))

    add("")
    add("DataSection")
    add("  TEXGOLD_WidthMasks:")
    add("  Data.l %d,%d,%d,%d" % (texture_width_mask(64), texture_width_mask(96),
                                texture_width_mask(128), texture_width_mask(256)))
    add("  TEXGOLD_Iscales:")
    add("  Data.l %d,%d,%d" % (iscale_value(256), iscale_value(512), iscale_value(2)))
    add("  TEXGOLD_ScalelightBins:")
    bins = [SCALELIGHT[level][scale] for level in range(LIGHT_LEVELS)
            for scale in range(LIGHT_MAXLIGHTSCALE)]
    for start in range(0, len(bins), 16):
        add("  Data.l " + ",".join(str(v) for v in bins[start:start + 16]))
    add("")
    for name in ("TI01", "TI02"):
        data = built[name]
        emit_ints(lines, "TEXGOLD_%s_Spans" % name,
                  [value for span in data["spans"] for value in [
                      span["sub"], span["seg"], span["line"], span["side"],
                      span["front"], span["back"], span["first"], span["last"],
                      0 if span["kind"] == "SOLID" else 1]])
        emit_ints(lines, "TEXGOLD_%s_PlanL" % name,
                  flat_l(data["plans"], L_TEXTURE_PLAN_FIELDS))
        emit_quads(lines, "TEXGOLD_%s_PlanQ" % name,
                   flat_q(data["plans"], Q_TEXTURE_PLAN_FIELDS))
        emit_ints(lines, "TEXGOLD_%s_SampleX" % name, data["scene"]["samples"])
        rows = []
        for sample in data["samples"]:
            rows.extend(sample)
        emit_bytes(lines, "TEXGOLD_%s_SampleRows" % name, rows)
        emit_bytes(lines, "TEXGOLD_%s_Frame" % name, data["frame"])
        add("  TEXGOLD_%s_SpanHash:" % name)
        add("  Data.q $%016X" % data["span_hash"])
        add("  TEXGOLD_%s_Hash:" % name)
        add("  Data.q $%016X" % data["hash"])
    add("EndDataSection")
    add("")
    add("CompilerEndIf")
    add("")

    with open(output_path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines))


def default_source():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)
    return os.path.join(repo_root, "..", "doom-original", "linuxdoom-1.10", "tables.c")


def print_built(built):
    for name in ("TI01", "TI02"):
        data = built[name]
        counters = data["counters"]
        print("scene %s:" % name)
        print("  spans %d, texture plans %d" % (len(data["spans"]), len(data["plans"])))
        for span in data["spans"]:
            print("  span sub=%d seg=%d line=%d side=%d front=%d back=%d x=%d..%d"
                  " kind=%s" % (span["sub"], span["seg"], span["line"], span["side"],
                                span["front"], span["back"], span["first"],
                                span["last"], span["kind"]))
        for plan in data["plans"]:
            print("  plan seg=%d x=%d..%d tiers middle=%d top=%d bottom=%d"
                  " masked=%d midtex=%d toptex=%d bottex=%d light=%d"
                  % (plan["Seg"], plan["FirstX"], plan["LastX"],
                     plan["MiddleTier"], plan["TopTier"], plan["BottomTier"],
                     plan["MaskedMid"], plan["MidTextureIndex"],
                     plan["TopTextureIndex"], plan["BottomTextureIndex"],
                     plan["LightNum"]))
        print("  cache composed=%d requested=%d reused=%d masked=%d short=%d"
              " allocations=%d" % (data["cache"]["composed"],
                                   data["cache"]["requested"],
                                   data["cache"]["reused"],
                                   data["cache"]["masked"],
                                   data["cache"]["short"],
                                   data["cache"]["allocations"]))
        print("  counters processed=%d texcols=%d pixels middle=%d upper=%d"
              " lower=%d total=%d ranges=%d empty=%d clipped=%d"
              % (counters["processed_columns"], counters["texture_columns"],
                 counters["middle_pixels"], counters["upper_pixels"],
                 counters["lower_pixels"], counters["drawn_pixels"],
                 counters["drawn_ranges"], counters["empty_columns"],
                 counters["clipped_columns"]))
        print("  samples=%d uncovered=%d fallbacks=%d nonzero=%d zero=%d"
              % (counters["samples"], counters["uncovered"], counters["fallbacks"],
                 data["nonzero"], data["zero"]))
        print("  frame hash 0x%016X" % data["hash"])


def main():
    parser = argparse.ArgumentParser(
        description="Generate DoomPB M3-06 independent textured wall fixture")
    parser.add_argument("--source", default=default_source(),
                        help="path to pinned tables.c")
    parser.add_argument("--output", default="",
                        help="output .pbi path (default: tests/fixtures)")
    args = parser.parse_args()

    base = load_base_oracle()
    tables = base.load_tables(args.source)
    tangent, sine, tant = tables
    built = {}
    for name, scene in (("TI01", TI01_SCENE), ("TI02", TI02_SCENE)):
        built[name] = build_scene(scene, tables, base)

    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)
    output = args.output
    if not output:
        output = os.path.join(repo_root, "tests", "fixtures",
                              "m3_wall_texture_golden.pbi")
    write_fixture(output, built)
    print("fixture: %s" % output)
    print_built(built)


if __name__ == "__main__":
    main()
