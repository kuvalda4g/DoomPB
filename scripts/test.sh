#!/usr/bin/env bash
#
# Runs the DoomPB verification suite on Linux/Unix.
#
# Performs a real PureBasic syntax check, a real build, the synthetic WAD
# header/directory, lump lookup/payload, PLAYPAL/patch, framebuffer/presentation,
# COLORMAP/PNAMES, TEXTURE1/TEXTURE2 definition, composite wall-texture,
# flat/sprite namespace, vanilla map binary and map loader/validation unit
# tests, M2 end-to-end resource/map integration tests, M3-01 fixed-point tests
# and optional IWAD harness, M3-02 BAM angle/exact-table/geometry tests with
# synthetic and optional IWAD integration, M3-03 deterministic BSP traversal
# unit B01-B48, its synthetic WAD/level/camera/trace integration I01-I03 and
# optional real-IWAD I04, M3-04 screen-projection/wall-clipping/occlusion unit
# WC01-WC52, its synthetic WAD/level/camera/online-visibility integration
# I01-I03 and optional real-IWAD catalog-aware I04, M3-05 vertical wall
# projection/tier rendering unit WP01-WP56, its synthetic WAD/level/camera/
# frame integration WI01-WI03 and optional real-IWAD wall-render WI04, M3-06
# textured wall-column/vanilla-lighting unit WT01-WT60, its synthetic texture/
# COLORMAP integration TI01-TI03 and optional real-IWAD textured TI04, M3-07
# synthetic release integration MR01-MR36 and RI01-RI03, optional real-IWAD
# release integration RI04, BEN01 wall-only frame timing, M4-01 visplane/
# real-flat unit PL01-PL60, its synthetic combined wall+flat integration
# PI01-PI03 and optional real-IWAD combined walls+flats PI04, and smoke tests
# against the produced executable: --version, --help, no-argument startup,
# unknown-option handling, --lump-info argument validation and nonblocking
# --show-title failures. No commercial game data and no display are needed for
# the synthetic suite. When IWAD_PATH points at an owner-owned legal IWAD,
# optional M3-03 I04, M3-04 I04, M3-05 WI04, M3-06 TI04, M3-07 RI04, M4-01 PI04
# and --map-info CLI checks additionally run read-only.
#
# Exit code 0 means every check passed; 1 means at least one check failed.

set -u
set -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"
BUILD_SCRIPT="${SCRIPT_DIR}/build.sh"
BIN="${REPO_ROOT}/build/DoomPB"
UNIT_TEST_BIN="${REPO_ROOT}/build/DoomPB-WadTests"
LUMP_TEST_BIN="${REPO_ROOT}/build/DoomPB-WadLumpTests"
GRAPHICS_TEST_BIN="${REPO_ROOT}/build/DoomPB-WadGraphicsTests"
DISPLAY_TEST_BIN="${REPO_ROOT}/build/DoomPB-WadDisplayTests"
RESOURCE_TEST_BIN="${REPO_ROOT}/build/DoomPB-WadResourceTests"
TEXTURE_DEF_TEST_BIN="${REPO_ROOT}/build/DoomPB-WadTextureDefsTests"
COMPOSITE_TEST_BIN="${REPO_ROOT}/build/DoomPB-WadCompositeTests"
FLAT_SPRITE_TEST_BIN="${REPO_ROOT}/build/DoomPB-WadFlatSpriteTests"
MAP_TYPES_TEST_BIN="${REPO_ROOT}/build/DoomPB-WadMapTypesTests"
MAP_LOADER_TEST_BIN="${REPO_ROOT}/build/DoomPB-WadMapLoaderTests"
INTEGRATION_TEST_BIN="${REPO_ROOT}/build/DoomPB-M2IntegrationTests"
FIXED_TEST_BIN="${REPO_ROOT}/build/DoomPB-FixedMathTests"
FIXED_IWAD_TEST_BIN="${REPO_ROOT}/build/DoomPB-M3FixedIwadTests"
GEOMETRY_TEST_BIN="${REPO_ROOT}/build/DoomPB-AngleGeometryTests"
GEOMETRY_INTEGRATION_TEST_BIN="${REPO_ROOT}/build/DoomPB-M3GeometryTests"
GEOMETRY_IWAD_TEST_BIN="${REPO_ROOT}/build/DoomPB-M3GeometryIwadTests"
BSP_TEST_BIN="${REPO_ROOT}/build/DoomPB-BspTraversalTests"
BSP_INTEGRATION_TEST_BIN="${REPO_ROOT}/build/DoomPB-M3BspTests"
BSP_IWAD_TEST_BIN="${REPO_ROOT}/build/DoomPB-M3BspIwadTests"
WALL_CLIPPING_TEST_BIN="${REPO_ROOT}/build/DoomPB-WallClippingTests"
WALL_CLIPPING_INTEGRATION_TEST_BIN="${REPO_ROOT}/build/DoomPB-M3WallClipTests"
WALL_CLIPPING_IWAD_TEST_BIN="${REPO_ROOT}/build/DoomPB-M3WallClipIwadTests"
WALL_PROJECTION_TEST_BIN="${REPO_ROOT}/build/DoomPB-WallProjectionTests"
WALL_RENDER_INTEGRATION_TEST_BIN="${REPO_ROOT}/build/DoomPB-M3WallRenderTests"
WALL_RENDER_IWAD_TEST_BIN="${REPO_ROOT}/build/DoomPB-M3WallRenderIwadTests"
WALL_TEXTURE_TEST_BIN="${REPO_ROOT}/build/DoomPB-WallTextureTests"
WALL_TEXTURE_INTEGRATION_TEST_BIN="${REPO_ROOT}/build/DoomPB-M3WallTextureTests"
WALL_TEXTURE_IWAD_TEST_BIN="${REPO_ROOT}/build/DoomPB-M3WallTextureIwadTests"
PLANE_TEST_BIN="${REPO_ROOT}/build/DoomPB-PlaneRenderTests"
PLANE_INTEGRATION_TEST_BIN="${REPO_ROOT}/build/DoomPB-M4PlaneTests"
PLANE_IWAD_TEST_BIN="${REPO_ROOT}/build/DoomPB-M4PlaneIwadTests"
M3_RELEASE_TEST_BIN="${REPO_ROOT}/build/DoomPB-M3ReleaseTests"
M3_RELEASE_IWAD_TEST_BIN="${REPO_ROOT}/build/DoomPB-M3ReleaseIwadTests"
M3_RELEASE_BENCHMARK_BIN="${REPO_ROOT}/build/DoomPB-M3ReleaseBenchmark"
IWAD_PATH="${IWAD_PATH:-}"
CHECKS=0
FAILURES=0
LAST_STATUS=0

run_build() {
    # Invoke through bash so a missing executable bit cannot break the tests.
    bash "${BUILD_SCRIPT}" "$@"
    LAST_STATUS=$?
}

# check_case <description> <expected-exit> <expected-egrep-pattern> [args...]
check_case() {
    local description="$1"
    local expected_status="$2"
    local pattern="$3"
    shift 3

    local output status
    output="$("${BIN}" "$@" 2>&1)"
    status=$?
    CHECKS=$((CHECKS + 1))

    if [ "${status}" -ne "${expected_status}" ]; then
        printf 'FAIL: %s (expected exit %s, got %s)\n' \
            "${description}" "${expected_status}" "${status}" >&2
        FAILURES=$((FAILURES + 1))
        return
    fi

    if [ -n "${pattern}" ] && ! printf '%s\n' "${output}" | grep -Eq -- "${pattern}"; then
        printf 'FAIL: %s (output did not match /%s/):\n%s\n' \
            "${description}" "${pattern}" "${output}" >&2
        FAILURES=$((FAILURES + 1))
        return
    fi

    printf 'PASS: %s\n' "${description}"
}

printf '== Syntax check ==\n'
run_build --check
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: PureBasic syntax check exits with 0\n'
else
    printf 'FAIL: PureBasic syntax check exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: syntax check failed.\n' >&2
    exit 1
fi

printf '\n== Build ==\n'
run_build
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: PureBasic build exits with 0\n'
else
    printf 'FAIL: PureBasic build exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: build failed.\n' >&2
    exit 1
fi

CHECKS=$((CHECKS + 1))
if [ -f "${BIN}" ]; then
    printf 'PASS: build output exists: %s\n' "${BIN}"
else
    printf 'FAIL: build output missing: %s\n' "${BIN}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: build output missing.\n' >&2
    exit 1
fi

printf '\n== WAD unit test build ==\n'
run_build --check --test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: WAD test syntax check exits with 0\n'
else
    printf 'FAIL: WAD test syntax check exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: WAD test syntax check failed.\n' >&2
    exit 1
fi

run_build --test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: WAD test build exits with 0\n'
else
    printf 'FAIL: WAD test build exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: WAD test build failed.\n' >&2
    exit 1
fi

CHECKS=$((CHECKS + 1))
if [ -f "${UNIT_TEST_BIN}" ]; then
    printf 'PASS: WAD test output exists: %s\n' "${UNIT_TEST_BIN}"
else
    printf 'FAIL: WAD test output missing: %s\n' "${UNIT_TEST_BIN}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: WAD test output missing.\n' >&2
    exit 1
fi

printf '\n== WAD header/directory unit tests ==\n'
"${UNIT_TEST_BIN}"
unit_status=$?
CHECKS=$((CHECKS + 1))
if [ "${unit_status}" -eq 0 ]; then
    printf 'PASS: synthetic WAD tests exit with 0\n'
else
    printf 'FAIL: synthetic WAD tests exit with %s\n' "${unit_status}" >&2
    FAILURES=$((FAILURES + 1))
fi

printf '\n== WAD lump lookup/payload test build ==\n'
run_build --check --lump-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: WAD lump test syntax check exits with 0\n'
else
    printf 'FAIL: WAD lump test syntax check exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: WAD lump test syntax check failed.\n' >&2
    exit 1
fi

run_build --lump-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: WAD lump test build exits with 0\n'
else
    printf 'FAIL: WAD lump test build exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: WAD lump test build failed.\n' >&2
    exit 1
fi

CHECKS=$((CHECKS + 1))
if [ -f "${LUMP_TEST_BIN}" ]; then
    printf 'PASS: WAD lump test output exists: %s\n' "${LUMP_TEST_BIN}"
else
    printf 'FAIL: WAD lump test output missing: %s\n' "${LUMP_TEST_BIN}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: WAD lump test output missing.\n' >&2
    exit 1
fi

printf '\n== WAD lump lookup/payload unit tests ==\n'
"${LUMP_TEST_BIN}"
lump_status=$?
CHECKS=$((CHECKS + 1))
if [ "${lump_status}" -eq 0 ]; then
    printf 'PASS: synthetic WAD lump tests exit with 0\n'
else
    printf 'FAIL: synthetic WAD lump tests exit with %s\n' "${lump_status}" >&2
    FAILURES=$((FAILURES + 1))
fi

printf '\n== WAD graphics decoder test build ==\n'
run_build --check --graphics-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: WAD graphics test syntax check exits with 0\n'
else
    printf 'FAIL: WAD graphics test syntax check exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: WAD graphics test syntax check failed.\n' >&2
    exit 1
fi

run_build --graphics-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: WAD graphics test build exits with 0\n'
else
    printf 'FAIL: WAD graphics test build exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: WAD graphics test build failed.\n' >&2
    exit 1
fi

CHECKS=$((CHECKS + 1))
if [ -f "${GRAPHICS_TEST_BIN}" ]; then
    printf 'PASS: WAD graphics test output exists: %s\n' "${GRAPHICS_TEST_BIN}"
else
    printf 'FAIL: WAD graphics test output missing: %s\n' "${GRAPHICS_TEST_BIN}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: WAD graphics test output missing.\n' >&2
    exit 1
fi

printf '\n== WAD PLAYPAL/patch decoder unit tests ==\n'
"${GRAPHICS_TEST_BIN}"
graphics_status=$?
CHECKS=$((CHECKS + 1))
if [ "${graphics_status}" -eq 0 ]; then
    printf 'PASS: synthetic WAD graphics tests exit with 0\n'
else
    printf 'FAIL: synthetic WAD graphics tests exit with %s\n' "${graphics_status}" >&2
    FAILURES=$((FAILURES + 1))
fi

printf '\n== WAD framebuffer/presentation test build ==\n'
run_build --check --display-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: WAD display test syntax check exits with 0\n'
else
    printf 'FAIL: WAD display test syntax check exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: WAD display test syntax check failed.\n' >&2
    exit 1
fi

run_build --display-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: WAD display test build exits with 0\n'
else
    printf 'FAIL: WAD display test build exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: WAD display test build failed.\n' >&2
    exit 1
fi

CHECKS=$((CHECKS + 1))
if [ -f "${DISPLAY_TEST_BIN}" ]; then
    printf 'PASS: WAD display test output exists: %s\n' "${DISPLAY_TEST_BIN}"
else
    printf 'FAIL: WAD display test output missing: %s\n' "${DISPLAY_TEST_BIN}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: WAD display test output missing.\n' >&2
    exit 1
fi

printf '\n== WAD framebuffer/presentation unit tests ==\n'
"${DISPLAY_TEST_BIN}"
display_status=$?
CHECKS=$((CHECKS + 1))
if [ "${display_status}" -eq 0 ]; then
    printf 'PASS: synthetic WAD display tests exit with 0\n'
else
    printf 'FAIL: synthetic WAD display tests exit with %s\n' "${display_status}" >&2
    FAILURES=$((FAILURES + 1))
fi

printf '\n== WAD COLORMAP/PNAMES test build ==\n'
run_build --check --resource-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: WAD resource test syntax check exits with 0\n'
else
    printf 'FAIL: WAD resource test syntax check exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: WAD resource test syntax check failed.\n' >&2
    exit 1
fi

run_build --resource-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: WAD resource test build exits with 0\n'
else
    printf 'FAIL: WAD resource test build exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: WAD resource test build failed.\n' >&2
    exit 1
fi

CHECKS=$((CHECKS + 1))
if [ -f "${RESOURCE_TEST_BIN}" ]; then
    printf 'PASS: WAD resource test output exists: %s\n' "${RESOURCE_TEST_BIN}"
else
    printf 'FAIL: WAD resource test output missing: %s\n' "${RESOURCE_TEST_BIN}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: WAD resource test output missing.\n' >&2
    exit 1
fi

printf '\n== WAD COLORMAP/PNAMES unit tests ==\n'
"${RESOURCE_TEST_BIN}"
resource_status=$?
CHECKS=$((CHECKS + 1))
if [ "${resource_status}" -eq 0 ]; then
    printf 'PASS: synthetic WAD resource tests exit with 0\n'
else
    printf 'FAIL: synthetic WAD resource tests exit with %s\n' "${resource_status}" >&2
    FAILURES=$((FAILURES + 1))
fi

printf '\n== WAD TEXTURE1/TEXTURE2 test build ==\n'
run_build --check --texture-def-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: WAD texture definition test syntax check exits with 0\n'
else
    printf 'FAIL: WAD texture definition test syntax check exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: WAD texture definition test syntax check failed.\n' >&2
    exit 1
fi

run_build --texture-def-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: WAD texture definition test build exits with 0\n'
else
    printf 'FAIL: WAD texture definition test build exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: WAD texture definition test build failed.\n' >&2
    exit 1
fi

CHECKS=$((CHECKS + 1))
if [ -f "${TEXTURE_DEF_TEST_BIN}" ]; then
    printf 'PASS: WAD texture definition test output exists: %s\n' "${TEXTURE_DEF_TEST_BIN}"
else
    printf 'FAIL: WAD texture definition test output missing: %s\n' "${TEXTURE_DEF_TEST_BIN}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: WAD texture definition test output missing.\n' >&2
    exit 1
fi

printf '\n== WAD TEXTURE1/TEXTURE2 unit tests ==\n'
"${TEXTURE_DEF_TEST_BIN}"
texture_status=$?
CHECKS=$((CHECKS + 1))
if [ "${texture_status}" -eq 0 ]; then
    printf 'PASS: synthetic WAD texture definition tests exit with 0\n'
else
    printf 'FAIL: synthetic WAD texture definition tests exit with %s\n' "${texture_status}" >&2
    FAILURES=$((FAILURES + 1))
fi

printf '\n== WAD composite texture test build ==\n'
run_build --check --composite-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: WAD composite test syntax check exits with 0\n'
else
    printf 'FAIL: WAD composite test syntax check exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: WAD composite test syntax check failed.\n' >&2
    exit 1
fi

run_build --composite-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: WAD composite test build exits with 0\n'
else
    printf 'FAIL: WAD composite test build exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: WAD composite test build failed.\n' >&2
    exit 1
fi

CHECKS=$((CHECKS + 1))
if [ -f "${COMPOSITE_TEST_BIN}" ]; then
    printf 'PASS: WAD composite test output exists: %s\n' "${COMPOSITE_TEST_BIN}"
else
    printf 'FAIL: WAD composite test output missing: %s\n' "${COMPOSITE_TEST_BIN}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: WAD composite test output missing.\n' >&2
    exit 1
fi

printf '\n== WAD composite texture unit tests ==\n'
"${COMPOSITE_TEST_BIN}"
composite_status=$?
CHECKS=$((CHECKS + 1))
if [ "${composite_status}" -eq 0 ]; then
    printf 'PASS: synthetic WAD composite tests exit with 0\n'
else
    printf 'FAIL: synthetic WAD composite tests exit with %s\n' "${composite_status}" >&2
    FAILURES=$((FAILURES + 1))
fi

printf '\n== WAD flat/sprite namespace test build ==\n'
run_build --check --flat-sprite-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: WAD flat/sprite test syntax check exits with 0\n'
else
    printf 'FAIL: WAD flat/sprite test syntax check exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: WAD flat/sprite test syntax check failed.\n' >&2
    exit 1
fi

run_build --flat-sprite-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: WAD flat/sprite test build exits with 0\n'
else
    printf 'FAIL: WAD flat/sprite test build exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: WAD flat/sprite test build failed.\n' >&2
    exit 1
fi

CHECKS=$((CHECKS + 1))
if [ -f "${FLAT_SPRITE_TEST_BIN}" ]; then
    printf 'PASS: WAD flat/sprite test output exists: %s\n' "${FLAT_SPRITE_TEST_BIN}"
else
    printf 'FAIL: WAD flat/sprite test output missing: %s\n' "${FLAT_SPRITE_TEST_BIN}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: WAD flat/sprite test output missing.\n' >&2
    exit 1
fi

printf '\n== WAD flat/sprite unit tests ==\n'
"${FLAT_SPRITE_TEST_BIN}"
flat_sprite_status=$?
CHECKS=$((CHECKS + 1))
if [ "${flat_sprite_status}" -eq 0 ]; then
    printf 'PASS: synthetic WAD flat/sprite tests exit with 0\n'
else
    printf 'FAIL: synthetic WAD flat/sprite tests exit with %s\n' "${flat_sprite_status}" >&2
    FAILURES=$((FAILURES + 1))
fi

printf '\n== WAD map binary test build ==\n'
run_build --check --map-types-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: WAD map types test syntax check exits with 0\n'
else
    printf 'FAIL: WAD map types test syntax check exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: WAD map types test syntax check failed.\n' >&2
    exit 1
fi

run_build --map-types-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: WAD map types test build exits with 0\n'
else
    printf 'FAIL: WAD map types test build exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: WAD map types test build failed.\n' >&2
    exit 1
fi

CHECKS=$((CHECKS + 1))
if [ -f "${MAP_TYPES_TEST_BIN}" ]; then
    printf 'PASS: WAD map types test output exists: %s\n' "${MAP_TYPES_TEST_BIN}"
else
    printf 'FAIL: WAD map types test output missing: %s\n' "${MAP_TYPES_TEST_BIN}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: WAD map types test output missing.\n' >&2
    exit 1
fi

printf '\n== WAD map binary unit tests ==\n'
"${MAP_TYPES_TEST_BIN}"
map_types_status=$?
CHECKS=$((CHECKS + 1))
if [ "${map_types_status}" -eq 0 ]; then
    printf 'PASS: synthetic WAD map binary tests exit with 0\n'
else
    printf 'FAIL: synthetic WAD map binary tests exit with %s\n' "${map_types_status}" >&2
    FAILURES=$((FAILURES + 1))
fi

printf '\n== WAD map loader/validation test build ==\n'
run_build --check --map-loader-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: WAD map loader test syntax check exits with 0\n'
else
    printf 'FAIL: WAD map loader test syntax check exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: WAD map loader test syntax check failed.\n' >&2
    exit 1
fi

run_build --map-loader-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: WAD map loader test build exits with 0\n'
else
    printf 'FAIL: WAD map loader test build exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: WAD map loader test build failed.\n' >&2
    exit 1
fi

CHECKS=$((CHECKS + 1))
if [ -f "${MAP_LOADER_TEST_BIN}" ]; then
    printf 'PASS: WAD map loader test output exists: %s\n' "${MAP_LOADER_TEST_BIN}"
else
    printf 'FAIL: WAD map loader test output missing: %s\n' "${MAP_LOADER_TEST_BIN}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: WAD map loader test output missing.\n' >&2
    exit 1
fi

printf '\n== WAD map loader/validation unit tests ==\n'
"${MAP_LOADER_TEST_BIN}"
map_loader_status=$?
CHECKS=$((CHECKS + 1))
if [ "${map_loader_status}" -eq 0 ]; then
    printf 'PASS: synthetic WAD map loader tests exit with 0\n'
else
    printf 'FAIL: synthetic WAD map loader tests exit with %s\n' "${map_loader_status}" >&2
    FAILURES=$((FAILURES + 1))
fi

printf '\n== M3-01 fixed-point math test build ==\n'
run_build --check --fixed-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3 fixed-point test syntax check exits with 0\n'
else
    printf 'FAIL: M3 fixed-point test syntax check exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3 fixed-point test syntax check failed.\n' >&2
    exit 1
fi

run_build --fixed-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3 fixed-point test build exits with 0\n'
else
    printf 'FAIL: M3 fixed-point test build exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3 fixed-point test build failed.\n' >&2
    exit 1
fi

CHECKS=$((CHECKS + 1))
if [ -f "${FIXED_TEST_BIN}" ]; then
    printf 'PASS: M3 fixed-point test output exists: %s\n' "${FIXED_TEST_BIN}"
else
    printf 'FAIL: M3 fixed-point test output missing: %s\n' "${FIXED_TEST_BIN}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3 fixed-point test output missing.\n' >&2
    exit 1
fi

printf '\n== M3-01 fixed-point math unit tests ==\n'
"${FIXED_TEST_BIN}"
fixed_status=$?
CHECKS=$((CHECKS + 1))
if [ "${fixed_status}" -eq 0 ]; then
    printf 'PASS: synthetic M3 fixed-point tests exit with 0\n'
else
    printf 'FAIL: synthetic M3 fixed-point tests exit with %s\n' "${fixed_status}" >&2
    FAILURES=$((FAILURES + 1))
fi

printf '\n== M3-01 optional IWAD fixed-point test build ==\n'
run_build --check --fixed-iwad-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3 optional IWAD fixed-point test syntax check exits with 0\n'
else
    printf 'FAIL: M3 optional IWAD fixed-point test syntax check exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3 optional IWAD fixed-point test syntax check failed.\n' >&2
    exit 1
fi

run_build --fixed-iwad-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3 optional IWAD fixed-point test build exits with 0\n'
else
    printf 'FAIL: M3 optional IWAD fixed-point test build exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3 optional IWAD fixed-point test build failed.\n' >&2
    exit 1
fi

CHECKS=$((CHECKS + 1))
if [ -f "${FIXED_IWAD_TEST_BIN}" ]; then
    printf 'PASS: M3 optional IWAD fixed-point test output exists: %s\n' "${FIXED_IWAD_TEST_BIN}"
else
    printf 'FAIL: M3 optional IWAD fixed-point test output missing: %s\n' "${FIXED_IWAD_TEST_BIN}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3 optional IWAD fixed-point test output missing.\n' >&2
    exit 1
fi

printf '\n== M3-01 optional IWAD fixed-point tests (no local path) ==\n'
fixed_iwad_output="$("${FIXED_IWAD_TEST_BIN}" 2>&1)"
fixed_iwad_status=$?
CHECKS=$((CHECKS + 1))
if [ "${fixed_iwad_status}" -eq 0 ]; then
    printf 'PASS: optional IWAD fixed-point tests exit with 0 without a WAD path\n'
else
    printf 'FAIL: optional IWAD fixed-point tests exit with %s\n' "${fixed_iwad_status}" >&2
    FAILURES=$((FAILURES + 1))
fi

CHECKS=$((CHECKS + 1))
if printf '%s\n' "${fixed_iwad_output}" | grep -Eq -- 'NOT RUN'; then
    printf 'PASS: optional IWAD fixed-point tests report NOT RUN without a path\n'
else
    printf 'FAIL: optional IWAD fixed-point tests did not report NOT RUN\n%s\n' \
        "${fixed_iwad_output}" >&2
    FAILURES=$((FAILURES + 1))
fi

printf '\n== M3-02 angle/geometry unit test build ==\n'
run_build --check --geometry-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3-02 angle/geometry test syntax check exits with 0\n'
else
    printf 'FAIL: M3-02 angle/geometry test syntax check exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-02 angle/geometry test syntax check failed.\n' >&2
    exit 1
fi

run_build --geometry-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3-02 angle/geometry test build exits with 0\n'
else
    printf 'FAIL: M3-02 angle/geometry test build exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-02 angle/geometry test build failed.\n' >&2
    exit 1
fi

CHECKS=$((CHECKS + 1))
if [ -f "${GEOMETRY_TEST_BIN}" ]; then
    printf 'PASS: M3-02 angle/geometry test output exists: %s\n' "${GEOMETRY_TEST_BIN}"
else
    printf 'FAIL: M3-02 angle/geometry test output missing: %s\n' "${GEOMETRY_TEST_BIN}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-02 angle/geometry test output missing.\n' >&2
    exit 1
fi

printf '\n== M3-02 angle/geometry unit tests ==\n'
"${GEOMETRY_TEST_BIN}"
geometry_status=$?
CHECKS=$((CHECKS + 1))
if [ "${geometry_status}" -eq 0 ]; then
    printf 'PASS: synthetic M3-02 angle/geometry tests exit with 0\n'
else
    printf 'FAIL: synthetic M3-02 angle/geometry tests exit with %s\n' "${geometry_status}" >&2
    FAILURES=$((FAILURES + 1))
fi

printf '\n== M3-02 synthetic geometry integration test build ==\n'
run_build --check --geometry-integration-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3-02 synthetic geometry integration test syntax check exits with 0\n'
else
    printf 'FAIL: M3-02 synthetic geometry integration test syntax check exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-02 synthetic geometry integration test syntax check failed.\n' >&2
    exit 1
fi

run_build --geometry-integration-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3-02 synthetic geometry integration test build exits with 0\n'
else
    printf 'FAIL: M3-02 synthetic geometry integration test build exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-02 synthetic geometry integration test build failed.\n' >&2
    exit 1
fi

CHECKS=$((CHECKS + 1))
if [ -f "${GEOMETRY_INTEGRATION_TEST_BIN}" ]; then
    printf 'PASS: M3-02 synthetic geometry integration test output exists: %s\n' "${GEOMETRY_INTEGRATION_TEST_BIN}"
else
    printf 'FAIL: M3-02 synthetic geometry integration test output missing: %s\n' "${GEOMETRY_INTEGRATION_TEST_BIN}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-02 synthetic geometry integration test output missing.\n' >&2
    exit 1
fi

printf '\n== M3-02 synthetic geometry integration tests ==\n'
"${GEOMETRY_INTEGRATION_TEST_BIN}"
geometry_integration_status=$?
CHECKS=$((CHECKS + 1))
if [ "${geometry_integration_status}" -eq 0 ]; then
    printf 'PASS: synthetic M3-02 geometry integration tests exit with 0\n'
else
    printf 'FAIL: synthetic M3-02 geometry integration tests exit with %s\n' "${geometry_integration_status}" >&2
    FAILURES=$((FAILURES + 1))
fi

printf '\n== M3-02 optional IWAD angle/geometry test build ==\n'
run_build --check --geometry-iwad-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3-02 optional IWAD geometry test syntax check exits with 0\n'
else
    printf 'FAIL: M3-02 optional IWAD geometry test syntax check exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-02 optional IWAD geometry test syntax check failed.\n' >&2
    exit 1
fi

run_build --geometry-iwad-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3-02 optional IWAD geometry test build exits with 0\n'
else
    printf 'FAIL: M3-02 optional IWAD geometry test build exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-02 optional IWAD geometry test build failed.\n' >&2
    exit 1
fi

CHECKS=$((CHECKS + 1))
if [ -f "${GEOMETRY_IWAD_TEST_BIN}" ]; then
    printf 'PASS: M3-02 optional IWAD geometry test output exists: %s\n' "${GEOMETRY_IWAD_TEST_BIN}"
else
    printf 'FAIL: M3-02 optional IWAD geometry test output missing: %s\n' "${GEOMETRY_IWAD_TEST_BIN}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-02 optional IWAD geometry test output missing.\n' >&2
    exit 1
fi

printf '\n== M3-02 optional IWAD angle/geometry tests (no local path) ==\n'
geometry_iwad_output="$("${GEOMETRY_IWAD_TEST_BIN}" 2>&1)"
geometry_iwad_status=$?
CHECKS=$((CHECKS + 1))
if [ "${geometry_iwad_status}" -eq 0 ]; then
    printf 'PASS: optional IWAD geometry tests exit with 0 without a WAD path\n'
else
    printf 'FAIL: optional IWAD geometry tests exit with %s\n' "${geometry_iwad_status}" >&2
    FAILURES=$((FAILURES + 1))
fi

CHECKS=$((CHECKS + 1))
if printf '%s\n' "${geometry_iwad_output}" | grep -Eq -- 'NOT RUN'; then
    printf 'PASS: optional IWAD geometry tests report NOT RUN without a path\n'
else
    printf 'FAIL: optional IWAD geometry tests did not report NOT RUN\n%s\n' \
        "${geometry_iwad_output}" >&2
    FAILURES=$((FAILURES + 1))
fi

printf '\n== M3-03 BSP traversal unit test build ==\n'
run_build --check --bsp-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3-03 BSP unit test syntax check exits with 0\n'
else
    printf 'FAIL: M3-03 BSP unit test syntax check exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-03 BSP unit test syntax check failed.\n' >&2
    exit 1
fi

run_build --bsp-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3-03 BSP unit test build exits with 0\n'
else
    printf 'FAIL: M3-03 BSP unit test build exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-03 BSP unit test build failed.\n' >&2
    exit 1
fi

CHECKS=$((CHECKS + 1))
if [ -f "${BSP_TEST_BIN}" ]; then
    printf 'PASS: M3-03 BSP unit test output exists: %s\n' "${BSP_TEST_BIN}"
else
    printf 'FAIL: M3-03 BSP unit test output missing: %s\n' "${BSP_TEST_BIN}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-03 BSP unit test output missing.\n' >&2
    exit 1
fi

printf '\n== M3-03 BSP traversal unit tests (B01-B48) ==\n'
bsp_unit_output="$("${BSP_TEST_BIN}" 2>&1)"
bsp_unit_status=$?
CHECKS=$((CHECKS + 1))
if [ "${bsp_unit_status}" -eq 0 ]; then
    printf 'PASS: synthetic M3-03 BSP traversal tests exit with 0\n'
else
    printf 'FAIL: synthetic M3-03 BSP traversal tests exit with %s\n' "${bsp_unit_status}" >&2
    FAILURES=$((FAILURES + 1))
fi
CHECKS=$((CHECKS + 1))
if printf '%s\n' "${bsp_unit_output}" | grep -Eq -- '^Cases: 48, assertions: 669, failures: 0$'; then
    printf 'PASS: M3-03 B01-B48 runs 48 cases/669 assertions/0 failures\n'
else
    printf 'FAIL: M3-03 B01-B48 case/assertion totals differ\n%s\n' "${bsp_unit_output}" >&2
    FAILURES=$((FAILURES + 1))
fi

printf '\n== M3-03 BSP synthetic integration test build ==\n'
run_build --check --bsp-integration-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3-03 BSP integration test syntax check exits with 0\n'
else
    printf 'FAIL: M3-03 BSP integration test syntax check exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-03 BSP integration test syntax check failed.\n' >&2
    exit 1
fi

run_build --bsp-integration-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3-03 BSP integration test build exits with 0\n'
else
    printf 'FAIL: M3-03 BSP integration test build exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-03 BSP integration test build failed.\n' >&2
    exit 1
fi

CHECKS=$((CHECKS + 1))
if [ -f "${BSP_INTEGRATION_TEST_BIN}" ]; then
    printf 'PASS: M3-03 BSP integration test output exists: %s\n' "${BSP_INTEGRATION_TEST_BIN}"
else
    printf 'FAIL: M3-03 BSP integration test output missing: %s\n' "${BSP_INTEGRATION_TEST_BIN}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-03 BSP integration test output missing.\n' >&2
    exit 1
fi

printf '\n== M3-03 BSP synthetic integration tests (I01-I03) ==\n'
bsp_integration_output="$("${BSP_INTEGRATION_TEST_BIN}" 2>&1)"
bsp_integration_status=$?
CHECKS=$((CHECKS + 1))
if [ "${bsp_integration_status}" -eq 0 ]; then
    printf 'PASS: synthetic M3-03 BSP integration tests exit with 0\n'
else
    printf 'FAIL: synthetic M3-03 BSP integration tests exit with %s\n' "${bsp_integration_status}" >&2
    FAILURES=$((FAILURES + 1))
fi
CHECKS=$((CHECKS + 1))
if printf '%s\n' "${bsp_integration_output}" | grep -Eq -- '^Cases: 3, assertions: 87, failures: 0$'; then
    printf 'PASS: M3-03 I01-I03 runs 3 cases/87 assertions/0 failures\n'
else
    printf 'FAIL: M3-03 I01-I03 case/assertion totals differ\n%s\n' "${bsp_integration_output}" >&2
    FAILURES=$((FAILURES + 1))
fi

printf '\n== M3-03 optional IWAD BSP integration test build ==\n'
run_build --check --bsp-iwad-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3-03 optional IWAD BSP test syntax check exits with 0\n'
else
    printf 'FAIL: M3-03 optional IWAD BSP test syntax check exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-03 optional IWAD BSP test syntax check failed.\n' >&2
    exit 1
fi

run_build --bsp-iwad-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3-03 optional IWAD BSP test build exits with 0\n'
else
    printf 'FAIL: M3-03 optional IWAD BSP test build exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-03 optional IWAD BSP test build failed.\n' >&2
    exit 1
fi

CHECKS=$((CHECKS + 1))
if [ -f "${BSP_IWAD_TEST_BIN}" ]; then
    printf 'PASS: M3-03 optional IWAD BSP test output exists: %s\n' "${BSP_IWAD_TEST_BIN}"
else
    printf 'FAIL: M3-03 optional IWAD BSP test output missing: %s\n' "${BSP_IWAD_TEST_BIN}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-03 optional IWAD BSP test output missing.\n' >&2
    exit 1
fi

printf '\n== M3-03 optional IWAD BSP integration tests ==\n'
if [ -z "${IWAD_PATH}" ]; then
    bsp_iwad_output="$("${BSP_IWAD_TEST_BIN}" 2>&1)"
    bsp_iwad_status=$?
    CHECKS=$((CHECKS + 1))
    if [ "${bsp_iwad_status}" -eq 0 ]; then
        printf 'PASS: optional IWAD BSP tests exit with 0 without a WAD path\n'
    else
        printf 'FAIL: optional IWAD BSP tests exit with %s\n' "${bsp_iwad_status}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${bsp_iwad_output}" | grep -Eq -- 'NOT RUN'; then
        printf 'PASS: optional IWAD BSP tests report NOT RUN without a path\n'
    else
        printf 'FAIL: optional IWAD BSP tests did not report NOT RUN\n%s\n' "${bsp_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
else
    CHECKS=$((CHECKS + 1))
    if [ -f "${IWAD_PATH}" ]; then
        printf 'PASS: explicit owner IWAD path exists\n'
    else
        printf 'FAIL: explicit owner IWAD path does not exist\n' >&2
        FAILURES=$((FAILURES + 1))
    fi
    bsp_iwad_output="$("${BSP_IWAD_TEST_BIN}" "${IWAD_PATH}" 2>&1)"
    bsp_iwad_status=$?
    CHECKS=$((CHECKS + 1))
    if [ "${bsp_iwad_status}" -eq 0 ]; then
        printf 'PASS: optional IWAD BSP E1M1/E1M2/E4M1 integration exits with 0\n'
    else
        printf 'FAIL: optional IWAD BSP integration exits with %s\n' "${bsp_iwad_status}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${bsp_iwad_output}" | grep -Eq -- '^RESULT: PASS'; then
        printf 'PASS: optional IWAD BSP integration reports PASS\n'
    else
        printf 'FAIL: optional IWAD BSP integration did not report PASS\n%s\n' "${bsp_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${bsp_iwad_output}" | grep -q -- 'E1M1: player-start camera'; then
        printf 'PASS: optional IWAD BSP integration actually ran E1M1\n'
    else
        printf 'FAIL: optional IWAD BSP integration E1M1 measurement missing\n%s\n' "${bsp_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${bsp_iwad_output}" | grep -q -- 'E4M1: player-start camera'; then
        printf 'PASS: optional IWAD BSP integration actually ran E4M1\n'
    else
        printf 'FAIL: optional IWAD BSP integration E4M1 measurement missing\n%s\n' "${bsp_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${bsp_iwad_output}" | grep -Eq -- 'owner IWAD remains unchanged'; then
        printf 'PASS: owner IWAD read-only size/MD5 unchanged\n'
    else
        printf 'FAIL: owner IWAD unchanged verification missing\n%s\n' "${bsp_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
fi

printf '\n== M3-04 wall-clipping unit test build ==\n'
run_build --check --wall-clipping-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3-04 wall-clipping unit test syntax check exits with 0\n'
else
    printf 'FAIL: M3-04 wall-clipping unit test syntax check exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-04 wall-clipping unit test syntax check failed.\n' >&2
    exit 1
fi

run_build --wall-clipping-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3-04 wall-clipping unit test build exits with 0\n'
else
    printf 'FAIL: M3-04 wall-clipping unit test build exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-04 wall-clipping unit test build failed.\n' >&2
    exit 1
fi

CHECKS=$((CHECKS + 1))
if [ -f "${WALL_CLIPPING_TEST_BIN}" ]; then
    printf 'PASS: M3-04 wall-clipping unit test output exists: %s\n' "${WALL_CLIPPING_TEST_BIN}"
else
    printf 'FAIL: M3-04 wall-clipping unit test output missing: %s\n' "${WALL_CLIPPING_TEST_BIN}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-04 wall-clipping unit test output missing.\n' >&2
    exit 1
fi

printf '\n== M3-04 wall-clipping unit tests (WC01-WC52) ==\n'
wall_clipping_unit_output="$("${WALL_CLIPPING_TEST_BIN}" 2>&1)"
wall_clipping_unit_status=$?
CHECKS=$((CHECKS + 1))
if [ "${wall_clipping_unit_status}" -eq 0 ]; then
    printf 'PASS: synthetic M3-04 wall-clipping unit tests exit with 0\n'
else
    printf 'FAIL: synthetic M3-04 wall-clipping unit tests exit with %s\n' "${wall_clipping_unit_status}" >&2
    FAILURES=$((FAILURES + 1))
fi
CHECKS=$((CHECKS + 1))
if printf '%s\n' "${wall_clipping_unit_output}" | grep -Eq -- '^Cases: 52, assertions: 474, failures: 0$'; then
    printf 'PASS: M3-04 WC01-WC52 runs 52 cases/474 assertions/0 failures\n'
else
    printf 'FAIL: M3-04 WC01-WC52 case/assertion totals differ\n%s\n' "${wall_clipping_unit_output}" >&2
    FAILURES=$((FAILURES + 1))
fi

printf '\n== M3-04 synthetic wall-clipping integration test build ==\n'
run_build --check --wall-clipping-integration-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3-04 wall-clipping integration test syntax check exits with 0\n'
else
    printf 'FAIL: M3-04 wall-clipping integration test syntax check exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-04 wall-clipping integration test syntax check failed.\n' >&2
    exit 1
fi

run_build --wall-clipping-integration-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3-04 wall-clipping integration test build exits with 0\n'
else
    printf 'FAIL: M3-04 wall-clipping integration test build exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-04 wall-clipping integration test build failed.\n' >&2
    exit 1
fi

CHECKS=$((CHECKS + 1))
if [ -f "${WALL_CLIPPING_INTEGRATION_TEST_BIN}" ]; then
    printf 'PASS: M3-04 synthetic wall-clipping integration test output exists: %s\n' "${WALL_CLIPPING_INTEGRATION_TEST_BIN}"
else
    printf 'FAIL: M3-04 synthetic wall-clipping integration test output missing: %s\n' "${WALL_CLIPPING_INTEGRATION_TEST_BIN}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-04 synthetic wall-clipping integration test output missing.\n' >&2
    exit 1
fi

printf '\n== M3-04 synthetic wall-clipping integration tests (I01-I03) ==\n'
wall_clipping_integration_output="$("${WALL_CLIPPING_INTEGRATION_TEST_BIN}" 2>&1)"
wall_clipping_integration_status=$?
CHECKS=$((CHECKS + 1))
if [ "${wall_clipping_integration_status}" -eq 0 ]; then
    printf 'PASS: synthetic M3-04 wall-clipping integration tests exit with 0\n'
else
    printf 'FAIL: synthetic M3-04 wall-clipping integration tests exit with %s\n' "${wall_clipping_integration_status}" >&2
    FAILURES=$((FAILURES + 1))
fi
CHECKS=$((CHECKS + 1))
if printf '%s\n' "${wall_clipping_integration_output}" | grep -Eq -- '^Cases: 3, assertions: 115, failures: 0$'; then
    printf 'PASS: M3-04 I01-I03 runs 3 cases/115 assertions/0 failures\n'
else
    printf 'FAIL: M3-04 I01-I03 case/assertion totals differ\n%s\n' "${wall_clipping_integration_output}" >&2
    FAILURES=$((FAILURES + 1))
fi

printf '\n== M3-04 optional IWAD wall-clipping test build ==\n'
run_build --check --wall-clipping-iwad-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3-04 optional IWAD wall-clipping test syntax check exits with 0\n'
else
    printf 'FAIL: M3-04 optional IWAD wall-clipping test syntax check exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-04 optional IWAD wall-clipping test syntax check failed.\n' >&2
    exit 1
fi

run_build --wall-clipping-iwad-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3-04 optional IWAD wall-clipping test build exits with 0\n'
else
    printf 'FAIL: M3-04 optional IWAD wall-clipping test build exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-04 optional IWAD wall-clipping test build failed.\n' >&2
    exit 1
fi

CHECKS=$((CHECKS + 1))
if [ -f "${WALL_CLIPPING_IWAD_TEST_BIN}" ]; then
    printf 'PASS: M3-04 optional IWAD wall-clipping test output exists: %s\n' "${WALL_CLIPPING_IWAD_TEST_BIN}"
else
    printf 'FAIL: M3-04 optional IWAD wall-clipping test output missing: %s\n' "${WALL_CLIPPING_IWAD_TEST_BIN}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-04 optional IWAD wall-clipping test output missing.\n' >&2
    exit 1
fi

printf '\n== M3-04 optional IWAD wall-clipping tests ==\n'
if [ -z "${IWAD_PATH}" ]; then
    wall_clipping_iwad_output="$("${WALL_CLIPPING_IWAD_TEST_BIN}" 2>&1)"
    wall_clipping_iwad_status=$?
    CHECKS=$((CHECKS + 1))
    if [ "${wall_clipping_iwad_status}" -eq 0 ]; then
        printf 'PASS: optional IWAD wall-clipping tests exit with 0 without a WAD path\n'
    else
        printf 'FAIL: optional IWAD wall-clipping tests exit with %s\n' "${wall_clipping_iwad_status}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${wall_clipping_iwad_output}" | grep -Eq -- 'NOT RUN'; then
        printf 'PASS: optional IWAD wall-clipping tests report NOT RUN without a path\n'
    else
        printf 'FAIL: optional IWAD wall-clipping tests did not report NOT RUN\n%s\n' "${wall_clipping_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
else
    CHECKS=$((CHECKS + 1))
    if [ -f "${IWAD_PATH}" ]; then
        printf 'PASS: explicit owner IWAD path exists\n'
    else
        printf 'FAIL: explicit owner IWAD path does not exist\n' >&2
        FAILURES=$((FAILURES + 1))
    fi
    wall_clipping_iwad_output="$("${WALL_CLIPPING_IWAD_TEST_BIN}" "${IWAD_PATH}" 2>&1)"
    wall_clipping_iwad_status=$?
    CHECKS=$((CHECKS + 1))
    if [ "${wall_clipping_iwad_status}" -eq 0 ]; then
        printf 'PASS: optional IWAD wall-clipping E1M1/E1M2/E4M1 integration exits with 0\n'
    else
        printf 'FAIL: optional IWAD wall-clipping integration exits with %s\n' "${wall_clipping_iwad_status}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${wall_clipping_iwad_output}" | grep -Eq -- '^RESULT: PASS'; then
        printf 'PASS: optional IWAD wall-clipping integration reports PASS\n'
    else
        printf 'FAIL: optional IWAD wall-clipping integration did not report PASS\n%s\n' "${wall_clipping_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${wall_clipping_iwad_output}" | grep -q -- 'E1M1: cull-free 238 nodes'; then
        printf 'PASS: optional IWAD wall-clipping integration actually measured E1M1\n'
    else
        printf 'FAIL: optional IWAD wall-clipping E1M1 measurement missing\n%s\n' "${wall_clipping_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${wall_clipping_iwad_output}" | grep -q -- 'E1M2: cull-free 447 nodes'; then
        printf 'PASS: optional IWAD wall-clipping integration actually measured E1M2\n'
    else
        printf 'FAIL: optional IWAD wall-clipping E1M2 measurement missing\n%s\n' "${wall_clipping_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${wall_clipping_iwad_output}" | grep -q -- 'E4M1: cull-free 195 nodes'; then
        printf 'PASS: optional IWAD wall-clipping integration actually measured E4M1\n'
    else
        printf 'FAIL: optional IWAD wall-clipping E4M1 measurement missing\n%s\n' "${wall_clipping_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${wall_clipping_iwad_output}" | grep -q -- 'match decoded seg/line/side/sector identity'; then
        printf 'PASS: optional IWAD wall-clipping spans were source-identity audited\n'
    else
        printf 'FAIL: optional IWAD wall-clipping source-identity audit line missing\n%s\n' "${wall_clipping_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${wall_clipping_iwad_output}" | grep -Eq -- 'owner IWAD remains unchanged'; then
        printf 'PASS: owner IWAD read-only size/MD5 unchanged\n'
    else
        printf 'FAIL: owner IWAD unchanged verification missing\n%s\n' "${wall_clipping_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
fi

printf '\n== M2 end-to-end integration test build ==\n'
run_build --check --integration-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M2 integration test syntax check exits with 0\n'
else
    printf 'FAIL: M2 integration test syntax check exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M2 integration test syntax check failed.\n' >&2
    exit 1
fi

run_build --integration-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M2 integration test build exits with 0\n'
else
    printf 'FAIL: M2 integration test build exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M2 integration test build failed.\n' >&2
    exit 1
fi

CHECKS=$((CHECKS + 1))
if [ -f "${INTEGRATION_TEST_BIN}" ]; then
    printf 'PASS: M2 integration test output exists: %s\n' "${INTEGRATION_TEST_BIN}"
else
    printf 'FAIL: M2 integration test output missing: %s\n' "${INTEGRATION_TEST_BIN}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M2 integration test output missing.\n' >&2
    exit 1
fi

printf '\n== M2 end-to-end integration tests ==\n'
if [ -n "${IWAD_PATH}" ] && [ -f "${IWAD_PATH}" ]; then
    "${INTEGRATION_TEST_BIN}" "${IWAD_PATH}"
else
    "${INTEGRATION_TEST_BIN}"
fi
integration_status=$?
CHECKS=$((CHECKS + 1))
if [ "${integration_status}" -eq 0 ]; then
    printf 'PASS: M2 integration tests (synthetic or owner-I04 mode) exit with 0\n'
else
    printf 'FAIL: M2 integration tests exit with %s\n' "${integration_status}" >&2
    FAILURES=$((FAILURES + 1))
fi

printf '\n== M3-05 wall projection unit test build ==\n'
run_build --check --wall-projection-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3-05 wall projection unit test syntax check exits with 0\n'
else
    printf 'FAIL: M3-05 wall projection unit test syntax check exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-05 wall projection unit test syntax check failed.\n' >&2
    exit 1
fi

run_build --wall-projection-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3-05 wall projection unit test build exits with 0\n'
else
    printf 'FAIL: M3-05 wall projection unit test build exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-05 wall projection unit test build failed.\n' >&2
    exit 1
fi

CHECKS=$((CHECKS + 1))
if [ -f "${WALL_PROJECTION_TEST_BIN}" ]; then
    printf 'PASS: M3-05 wall projection unit test output exists: %s\n' "${WALL_PROJECTION_TEST_BIN}"
else
    printf 'FAIL: M3-05 wall projection unit test output missing: %s\n' "${WALL_PROJECTION_TEST_BIN}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-05 wall projection unit test output missing.\n' >&2
    exit 1
fi

printf '\n== M3-05 wall projection unit tests (WP01-WP56) ==\n'
wall_projection_unit_output="$("${WALL_PROJECTION_TEST_BIN}" 2>&1)"
wall_projection_unit_status=$?
CHECKS=$((CHECKS + 1))
if [ "${wall_projection_unit_status}" -eq 0 ]; then
    printf 'PASS: synthetic M3-05 wall projection unit tests exit with 0\n'
else
    printf 'FAIL: synthetic M3-05 wall projection unit tests exit with %s\n' "${wall_projection_unit_status}" >&2
    FAILURES=$((FAILURES + 1))
fi
CHECKS=$((CHECKS + 1))
if printf '%s\n' "${wall_projection_unit_output}" | grep -q -- 'Cases: 56, assertions: 738, failures: 0'; then
    printf 'PASS: M3-05 WP01-WP56 runs 56 cases/738 assertions/0 failures\n'
else
    printf 'FAIL: M3-05 WP01-WP56 case/assertion totals differ\n%s\n' "${wall_projection_unit_output}" >&2
    FAILURES=$((FAILURES + 1))
fi

printf '\n== M3-05 synthetic wall-render integration test build ==\n'
run_build --check --wall-render-integration-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3-05 synthetic wall-render integration test syntax check exits with 0\n'
else
    printf 'FAIL: M3-05 synthetic wall-render integration test syntax check exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-05 synthetic wall-render integration test syntax check failed.\n' >&2
    exit 1
fi

run_build --wall-render-integration-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3-05 synthetic wall-render integration test build exits with 0\n'
else
    printf 'FAIL: M3-05 synthetic wall-render integration test build exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-05 synthetic wall-render integration test build failed.\n' >&2
    exit 1
fi

CHECKS=$((CHECKS + 1))
if [ -f "${WALL_RENDER_INTEGRATION_TEST_BIN}" ]; then
    printf 'PASS: M3-05 synthetic wall-render test output exists: %s\n' "${WALL_RENDER_INTEGRATION_TEST_BIN}"
else
    printf 'FAIL: M3-05 synthetic wall-render test output missing: %s\n' "${WALL_RENDER_INTEGRATION_TEST_BIN}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-05 synthetic wall-render test output missing.\n' >&2
    exit 1
fi

printf '\n== M3-05 synthetic wall-render integration tests (WI01-WI03) ==\n'
wall_render_integration_output="$("${WALL_RENDER_INTEGRATION_TEST_BIN}" 2>&1)"
wall_render_integration_status=$?
CHECKS=$((CHECKS + 1))
if [ "${wall_render_integration_status}" -eq 0 ]; then
    printf 'PASS: synthetic M3-05 wall-render integration tests exit with 0\n'
else
    printf 'FAIL: synthetic M3-05 wall-render integration tests exit with %s\n' "${wall_render_integration_status}" >&2
    FAILURES=$((FAILURES + 1))
fi
CHECKS=$((CHECKS + 1))
if printf '%s\n' "${wall_render_integration_output}" | grep -q -- 'Cases: 3, assertions: 147, failures: 0'; then
    printf 'PASS: M3-05 WI01-WI03 runs 3 cases/147 assertions/0 failures\n'
else
    printf 'FAIL: M3-05 WI01-WI03 case/assertion totals differ\n%s\n' "${wall_render_integration_output}" >&2
    FAILURES=$((FAILURES + 1))
fi

printf '\n== M3-05 optional IWAD wall-render test build ==\n'
run_build --check --wall-render-iwad-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3-05 optional IWAD wall-render test syntax check exits with 0\n'
else
    printf 'FAIL: M3-05 optional IWAD wall-render test syntax check exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-05 optional IWAD wall-render test syntax check failed.\n' >&2
    exit 1
fi

run_build --wall-render-iwad-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3-05 optional IWAD wall-render test build exits with 0\n'
else
    printf 'FAIL: M3-05 optional IWAD wall-render test build exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-05 optional IWAD wall-render test build failed.\n' >&2
    exit 1
fi

CHECKS=$((CHECKS + 1))
if [ -f "${WALL_RENDER_IWAD_TEST_BIN}" ]; then
    printf 'PASS: M3-05 optional IWAD wall-render test output exists: %s\n' "${WALL_RENDER_IWAD_TEST_BIN}"
else
    printf 'FAIL: M3-05 optional IWAD wall-render test output missing: %s\n' "${WALL_RENDER_IWAD_TEST_BIN}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-05 optional IWAD wall-render test output missing.\n' >&2
    exit 1
fi

printf '\n== M3-05 optional IWAD wall-render tests ==\n'
if [ -z "${IWAD_PATH}" ]; then
    wall_render_iwad_output="$("${WALL_RENDER_IWAD_TEST_BIN}" 2>&1)"
    wall_render_iwad_status=$?
    CHECKS=$((CHECKS + 1))
    if [ "${wall_render_iwad_status}" -eq 0 ]; then
        printf 'PASS: optional IWAD wall-render tests exit with 0 without a WAD path\n'
    else
        printf 'FAIL: optional IWAD wall-render tests exit with %s\n' "${wall_render_iwad_status}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${wall_render_iwad_output}" | grep -Eq -- 'NOT RUN'; then
        printf 'PASS: optional IWAD wall-render tests report NOT RUN without a path\n'
    else
        printf 'FAIL: optional IWAD wall-render tests did not report NOT RUN\n%s\n' "${wall_render_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
else
    CHECKS=$((CHECKS + 1))
    if [ -f "${IWAD_PATH}" ]; then
        printf 'PASS: explicit owner IWAD path exists\n'
    else
        printf 'FAIL: explicit owner IWAD path does not exist\n' >&2
        FAILURES=$((FAILURES + 1))
    fi
    wall_render_iwad_output="$("${WALL_RENDER_IWAD_TEST_BIN}" "${IWAD_PATH}" 2>&1)"
    wall_render_iwad_status=$?
    CHECKS=$((CHECKS + 1))
    if [ "${wall_render_iwad_status}" -eq 0 ]; then
        printf 'PASS: optional IWAD wall-render E1M1/E1M2/E4M1 frame integration exits with 0\n'
    else
        printf 'FAIL: optional IWAD wall-render integration exits with %s\n' "${wall_render_iwad_status}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${wall_render_iwad_output}" | grep -Eq -- '^RESULT: PASS'; then
        printf 'PASS: optional IWAD wall-render integration reports PASS\n'
    else
        printf 'FAIL: optional IWAD wall-render integration did not report PASS\n%s\n' "${wall_render_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${wall_render_iwad_output}" | grep -q -- 'Cases: 1, assertions: 288, failures: 0'; then
        printf 'PASS: optional IWAD wall-render WI04 runs 1 case/288 assertions/0 failures\n'
    else
        printf 'FAIL: optional IWAD wall-render WI04 case/assertion totals differ\n%s\n' "${wall_render_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${wall_render_iwad_output}" | grep -q -- 'E1M1: frame spans 35'; then
        printf 'PASS: optional IWAD wall-render actually rendered E1M1\n'
    else
        printf 'FAIL: optional IWAD E1M1 frame measurement missing\n%s\n' "${wall_render_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${wall_render_iwad_output}" | grep -q -- 'E1M2: frame spans 54'; then
        printf 'PASS: optional IWAD wall-render actually rendered E1M2\n'
    else
        printf 'FAIL: optional IWAD E1M2 frame measurement missing\n%s\n' "${wall_render_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${wall_render_iwad_output}" | grep -q -- 'E4M1: frame spans 69'; then
        printf 'PASS: optional IWAD wall-render actually rendered E4M1\n'
    else
        printf 'FAIL: optional IWAD E4M1 frame measurement missing\n%s\n' "${wall_render_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${wall_render_iwad_output}" | grep -q -- 'frame FNV-1a64 4A923E4D357C7BD1'; then
        printf 'PASS: optional IWAD E1M1 locked frame hash reproduced\n'
    else
        printf 'FAIL: optional IWAD E1M1 frame hash missing\n%s\n' "${wall_render_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${wall_render_iwad_output}" | grep -q -- 'frame FNV-1a64 0C9627E5C2FD8D35'; then
        printf 'PASS: optional IWAD E1M2 locked frame hash reproduced\n'
    else
        printf 'FAIL: optional IWAD E1M2 frame hash missing\n%s\n' "${wall_render_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${wall_render_iwad_output}" | grep -q -- 'frame FNV-1a64 9AEB8BDD16834359'; then
        printf 'PASS: optional IWAD E4M1 locked frame hash reproduced\n'
    else
        printf 'FAIL: optional IWAD E4M1 frame hash missing\n%s\n' "${wall_render_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${wall_render_iwad_output}" | grep -q -- 'FNV-1a64 spans 74B485154CE29B0B, counters 7ADB45DBF2611B77'; then
        printf 'PASS: optional IWAD E1M1 M3-04 span/counters preserved\n'
    else
        printf 'FAIL: optional IWAD E1M1 M3-04 span/counter preservation line missing\n%s\n' "${wall_render_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${wall_render_iwad_output}" | grep -q -- 'FNV-1a64 spans 8AC0627513C4B619, counters 83CAB0E1049B850A'; then
        printf 'PASS: optional IWAD E1M2 M3-04 span/counters preserved\n'
    else
        printf 'FAIL: optional IWAD E1M2 M3-04 span/counter preservation line missing\n%s\n' "${wall_render_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${wall_render_iwad_output}" | grep -q -- 'FNV-1a64 spans 9FD0B15A0F33197E, counters CCAA2442EB270717'; then
        printf 'PASS: optional IWAD E4M1 M3-04 span/counters preserved\n'
    else
        printf 'FAIL: optional IWAD E4M1 M3-04 span/counter preservation line missing\n%s\n' "${wall_render_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${wall_render_iwad_output}" | grep -Eq -- 'owner IWAD remains unchanged'; then
        printf 'PASS: owner IWAD read-only size/MD5 unchanged\n'
    else
        printf 'FAIL: owner IWAD unchanged verification missing\n%s\n' "${wall_render_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
fi

printf '\n== M3-06 textured wall unit test build ==\n'
run_build --check --wall-texture-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3-06 textured wall unit test syntax check exits with 0\n'
else
    printf 'FAIL: M3-06 textured wall unit test syntax check exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-06 textured wall unit test syntax check failed.\n' >&2
    exit 1
fi

run_build --wall-texture-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3-06 textured wall unit test build exits with 0\n'
else
    printf 'FAIL: M3-06 textured wall unit test build exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-06 textured wall unit test build failed.\n' >&2
    exit 1
fi

CHECKS=$((CHECKS + 1))
if [ -f "${WALL_TEXTURE_TEST_BIN}" ]; then
    printf 'PASS: M3-06 textured wall unit test output exists: %s\n' "${WALL_TEXTURE_TEST_BIN}"
else
    printf 'FAIL: M3-06 textured wall unit test output missing: %s\n' "${WALL_TEXTURE_TEST_BIN}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-06 textured wall unit test output missing.\n' >&2
    exit 1
fi

printf '\n== M3-06 textured wall unit tests (WT01-WT60) ==\n'
wall_texture_unit_output="$("${WALL_TEXTURE_TEST_BIN}" 2>&1)"
wall_texture_unit_status=$?
CHECKS=$((CHECKS + 1))
if [ "${wall_texture_unit_status}" -eq 0 ]; then
    printf 'PASS: synthetic M3-06 textured wall unit tests exit with 0\n'
else
    printf 'FAIL: synthetic M3-06 textured wall unit tests exit with %s\n' "${wall_texture_unit_status}" >&2
    FAILURES=$((FAILURES + 1))
fi
CHECKS=$((CHECKS + 1))
if printf '%s\n' "${wall_texture_unit_output}" | grep -Eq -- '^RESULT: PASS'; then
    printf 'PASS: M3-06 WT01-WT60 reports PASS\n'
else
    printf 'FAIL: M3-06 textured wall unit suite did not report PASS\n%s\n' "${wall_texture_unit_output}" >&2
    FAILURES=$((FAILURES + 1))
fi
CHECKS=$((CHECKS + 1))
if printf '%s\n' "${wall_texture_unit_output}" | grep -q -- '[WT60]'; then
    printf 'PASS: M3-06 unit suite actually executed WT60\n'
else
    printf 'FAIL: M3-06 WT60 execution marker missing\n%s\n' "${wall_texture_unit_output}" >&2
    FAILURES=$((FAILURES + 1))
fi

printf '\n== M3-06 synthetic textured integration test build ==\n'
run_build --check --wall-texture-integration-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3-06 synthetic textured integration test syntax check exits with 0\n'
else
    printf 'FAIL: M3-06 synthetic textured integration test syntax check exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-06 synthetic textured integration test syntax check failed.\n' >&2
    exit 1
fi

run_build --wall-texture-integration-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3-06 synthetic textured integration test build exits with 0\n'
else
    printf 'FAIL: M3-06 synthetic textured integration test build exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-06 synthetic textured integration test build failed.\n' >&2
    exit 1
fi

CHECKS=$((CHECKS + 1))
if [ -f "${WALL_TEXTURE_INTEGRATION_TEST_BIN}" ]; then
    printf 'PASS: M3-06 synthetic textured integration output exists: %s\n' "${WALL_TEXTURE_INTEGRATION_TEST_BIN}"
else
    printf 'FAIL: M3-06 synthetic textured integration output missing: %s\n' "${WALL_TEXTURE_INTEGRATION_TEST_BIN}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-06 synthetic textured integration output missing.\n' >&2
    exit 1
fi

printf '\n== M3-06 synthetic textured integration tests (TI01-TI03) ==\n'
wall_texture_integration_output="$("${WALL_TEXTURE_INTEGRATION_TEST_BIN}" 2>&1)"
wall_texture_integration_status=$?
CHECKS=$((CHECKS + 1))
if [ "${wall_texture_integration_status}" -eq 0 ]; then
    printf 'PASS: synthetic M3-06 textured integration tests exit with 0\n'
else
    printf 'FAIL: synthetic M3-06 textured integration tests exit with %s\n' "${wall_texture_integration_status}" >&2
    FAILURES=$((FAILURES + 1))
fi
CHECKS=$((CHECKS + 1))
if printf '%s\n' "${wall_texture_integration_output}" | grep -Eq -- '^RESULT: PASS'; then
    printf 'PASS: M3-06 TI01-TI03 reports PASS\n'
else
    printf 'FAIL: M3-06 synthetic textured integration did not report PASS\n%s\n' "${wall_texture_integration_output}" >&2
    FAILURES=$((FAILURES + 1))
fi
CHECKS=$((CHECKS + 1))
if printf '%s\n' "${wall_texture_integration_output}" | grep -q -- '[TI03]'; then
    printf 'PASS: M3-06 synthetic textured integration actually executed TI03\n'
else
    printf 'FAIL: M3-06 TI03 execution marker missing\n%s\n' "${wall_texture_integration_output}" >&2
    FAILURES=$((FAILURES + 1))
fi

printf '\n== M3-06 optional IWAD textured integration test build ==\n'
run_build --check --wall-texture-iwad-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3-06 optional IWAD textured integration syntax check exits with 0\n'
else
    printf 'FAIL: M3-06 optional IWAD textured integration syntax check exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-06 optional IWAD textured integration syntax check failed.\n' >&2
    exit 1
fi

run_build --wall-texture-iwad-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3-06 optional IWAD textured integration build exits with 0\n'
else
    printf 'FAIL: M3-06 optional IWAD textured integration build exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-06 optional IWAD textured integration build failed.\n' >&2
    exit 1
fi

CHECKS=$((CHECKS + 1))
if [ -f "${WALL_TEXTURE_IWAD_TEST_BIN}" ]; then
    printf 'PASS: M3-06 optional IWAD textured integration output exists: %s\n' "${WALL_TEXTURE_IWAD_TEST_BIN}"
else
    printf 'FAIL: M3-06 optional IWAD textured integration output missing: %s\n' "${WALL_TEXTURE_IWAD_TEST_BIN}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-06 optional IWAD textured integration output missing.\n' >&2
    exit 1
fi

printf '\n== M3-06 optional IWAD textured integration tests (TI04) ==\n'
if [ -z "${IWAD_PATH}" ]; then
    wall_texture_iwad_output="$("${WALL_TEXTURE_IWAD_TEST_BIN}" 2>&1)"
    wall_texture_iwad_status=$?
    CHECKS=$((CHECKS + 1))
    if [ "${wall_texture_iwad_status}" -eq 0 ]; then
        printf 'PASS: optional M3-06 IWAD textured tests exit with 0 without a WAD path\n'
    else
        printf 'FAIL: optional M3-06 IWAD textured tests exit with %s\n' "${wall_texture_iwad_status}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${wall_texture_iwad_output}" | grep -q -- 'NOT RUN'; then
        printf 'PASS: optional M3-06 IWAD textured tests report NOT RUN without a path\n'
    else
        printf 'FAIL: optional M3-06 IWAD textured tests did not report NOT RUN\n%s\n' "${wall_texture_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
else
    CHECKS=$((CHECKS + 1))
    if [ -f "${IWAD_PATH}" ]; then
        printf 'PASS: explicit owner IWAD path exists for M3-06\n'
    else
        printf 'FAIL: explicit owner IWAD path does not exist for M3-06\n' >&2
        FAILURES=$((FAILURES + 1))
    fi
    wall_texture_iwad_output="$("${WALL_TEXTURE_IWAD_TEST_BIN}" "${IWAD_PATH}" 2>&1)"
    wall_texture_iwad_status=$?
    CHECKS=$((CHECKS + 1))
    if [ "${wall_texture_iwad_status}" -eq 0 ]; then
        printf 'PASS: optional M3-06 IWAD textured integration exits with 0\n'
    else
        printf 'FAIL: optional M3-06 IWAD textured integration exits with %s\n' "${wall_texture_iwad_status}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${wall_texture_iwad_output}" | grep -Eq -- '^RESULT: PASS'; then
        printf 'PASS: optional M3-06 IWAD textured integration reports PASS\n'
    else
        printf 'FAIL: optional M3-06 IWAD textured integration did not report PASS\n%s\n' "${wall_texture_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    for map_name in E1M1 E1M2 E4M1; do
        CHECKS=$((CHECKS + 1))
        if printf '%s\n' "${wall_texture_iwad_output}" |
            grep -q -- "${map_name} transactional textured frame"; then
            printf 'PASS: optional M3-06 actually rendered %s textured frame\n' "${map_name}"
        else
            printf 'FAIL: optional M3-06 %s textured frame measurement missing\n%s\n' "${map_name}" "${wall_texture_iwad_output}" >&2
            FAILURES=$((FAILURES + 1))
        fi
    done
    for hash in 4A923E4D357C7BD1 0C9627E5C2FD8D35 9AEB8BDD16834359; do
        CHECKS=$((CHECKS + 1))
        if printf '%s\n' "${wall_texture_iwad_output}" | grep -q -- "${hash}"; then
            printf 'PASS: optional M3-06 M3-05 debug hash %s preserved\n' "${hash}"
        else
            printf 'FAIL: optional M3-06 M3-05 debug hash %s missing\n%s\n' "${hash}" "${wall_texture_iwad_output}" >&2
            FAILURES=$((FAILURES + 1))
        fi
    done
    for fingerprint in 74B485154CE29B0B 7ADB45DBF2611B77 8AC0627513C4B619 83CAB0E1049B850A 9FD0B15A0F33197E CCAA2442EB270717; do
        CHECKS=$((CHECKS + 1))
        if printf '%s\n' "${wall_texture_iwad_output}" | grep -q -- "${fingerprint}"; then
            printf 'PASS: optional M3-06 M3-04 fingerprint %s preserved\n' "${fingerprint}"
        else
            printf 'FAIL: optional M3-06 M3-04 fingerprint %s missing\n%s\n' "${fingerprint}" "${wall_texture_iwad_output}" >&2
            FAILURES=$((FAILURES + 1))
        fi
    done
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${wall_texture_iwad_output}" | grep -q -- 'repeat full 64,000-byte textured frame byte-for-byte identical'; then
        printf 'PASS: optional M3-06 textured frames repeat byte-for-byte\n'
    else
        printf 'FAIL: optional M3-06 textured repeat measurement missing\n%s\n' "${wall_texture_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${wall_texture_iwad_output}" | grep -Eq -- 'owner IWAD remains unchanged'; then
        printf 'PASS: optional M3-06 owner IWAD read-only unchanged\n'
    else
        printf 'FAIL: optional M3-06 owner IWAD unchanged verification missing\n%s\n' "${wall_texture_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
fi

printf '\n== M3-07 synthetic release integration test build ==\n'
run_build --check --m3-release-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3-07 synthetic release test syntax check exits with 0\n'
else
    printf 'FAIL: M3-07 synthetic release test syntax check exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-07 synthetic release test syntax check failed.\n' >&2
    exit 1
fi

run_build --m3-release-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3-07 synthetic release test build exits with 0\n'
else
    printf 'FAIL: M3-07 synthetic release test build exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-07 synthetic release test build failed.\n' >&2
    exit 1
fi

CHECKS=$((CHECKS + 1))
if [ -f "${M3_RELEASE_TEST_BIN}" ]; then
    printf 'PASS: M3-07 synthetic release test output exists: %s\n' "${M3_RELEASE_TEST_BIN}"
else
    printf 'FAIL: M3-07 synthetic release test output missing: %s\n' "${M3_RELEASE_TEST_BIN}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-07 synthetic release test output missing.\n' >&2
    exit 1
fi

printf '\n== M3-07 synthetic release integration tests (MR01-MR36, RI01-RI03) ==\n'
m3_release_output="$("${M3_RELEASE_TEST_BIN}" 2>&1)"
m3_release_status=$?
CHECKS=$((CHECKS + 1))
if [ "${m3_release_status}" -eq 0 ]; then
    printf 'PASS: synthetic M3-07 release integration tests exit with 0\n'
else
    printf 'FAIL: synthetic M3-07 release integration tests exit with %s\n' "${m3_release_status}" >&2
    FAILURES=$((FAILURES + 1))
fi
CHECKS=$((CHECKS + 1))
if printf '%s\n' "${m3_release_output}" | grep -Eq -- '^RESULT: PASS'; then
    printf 'PASS: M3-07 synthetic release integration reports PASS\n'
else
    printf 'FAIL: M3-07 synthetic release integration did not report PASS\n%s\n' "${m3_release_output}" >&2
    FAILURES=$((FAILURES + 1))
fi
CHECKS=$((CHECKS + 1))
if printf '%s\n' "${m3_release_output}" | grep -q -- 'Cases: 39, assertions: 444, failures: 0'; then
    printf 'PASS: M3-07 runs 39 cases/444 assertions/0 failures\n'
else
    printf 'FAIL: M3-07 synthetic release case/assertion totals differ\n%s\n' "${m3_release_output}" >&2
    FAILURES=$((FAILURES + 1))
fi
for marker in '[MR36]' '[RI01]' '[RI03]'; do
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${m3_release_output}" | grep -q -- "${marker}"; then
        printf 'PASS: M3-07 synthetic suite actually executed %s\n' "${marker}"
    else
        printf 'FAIL: M3-07 synthetic release execution marker %s missing\n%s\n' "${marker}" "${m3_release_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
done

printf '\n== M3-07 optional IWAD release integration test build ==\n'
run_build --check --m3-release-iwad-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3-07 optional IWAD release test syntax check exits with 0\n'
else
    printf 'FAIL: M3-07 optional IWAD release test syntax check exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-07 optional IWAD release test syntax check failed.\n' >&2
    exit 1
fi

run_build --m3-release-iwad-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3-07 optional IWAD release test build exits with 0\n'
else
    printf 'FAIL: M3-07 optional IWAD release test build exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-07 optional IWAD release test build failed.\n' >&2
    exit 1
fi

CHECKS=$((CHECKS + 1))
if [ -f "${M3_RELEASE_IWAD_TEST_BIN}" ]; then
    printf 'PASS: M3-07 optional IWAD release test output exists: %s\n' "${M3_RELEASE_IWAD_TEST_BIN}"
else
    printf 'FAIL: M3-07 optional IWAD release test output missing: %s\n' "${M3_RELEASE_IWAD_TEST_BIN}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-07 optional IWAD release test output missing.\n' >&2
    exit 1
fi

printf '\n== M3-07 optional IWAD release integration tests (RI04) ==\n'
if [ -z "${IWAD_PATH}" ]; then
    m3_release_iwad_output="$("${M3_RELEASE_IWAD_TEST_BIN}" 2>&1)"
    m3_release_iwad_status=$?
    CHECKS=$((CHECKS + 1))
    if [ "${m3_release_iwad_status}" -eq 0 ]; then
        printf 'PASS: optional M3-07 RI04 tests exit with 0 without a WAD path\n'
    else
        printf 'FAIL: optional M3-07 RI04 tests exit with %s\n' "${m3_release_iwad_status}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${m3_release_iwad_output}" | grep -q -- 'NOT RUN'; then
        printf 'PASS: optional M3-07 RI04 tests report NOT RUN without a path\n'
    else
        printf 'FAIL: optional M3-07 RI04 tests did not report NOT RUN\n%s\n' "${m3_release_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${m3_release_iwad_output}" | grep -q -- 'Cases: 0, assertions: 0, failures: 0'; then
        printf 'PASS: optional M3-07 RI04 no-argument mode is clean\n'
    else
        printf 'FAIL: optional M3-07 RI04 no-argument totals differ\n%s\n' "${m3_release_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
else
    CHECKS=$((CHECKS + 1))
    if [ -f "${IWAD_PATH}" ]; then
        printf 'PASS: explicit owner IWAD path exists for M3-07\n'
    else
        printf 'FAIL: explicit owner IWAD path does not exist for M3-07\n' >&2
        FAILURES=$((FAILURES + 1))
    fi
    m3_release_iwad_output="$("${M3_RELEASE_IWAD_TEST_BIN}" "${IWAD_PATH}" 2>&1)"
    m3_release_iwad_status=$?
    CHECKS=$((CHECKS + 1))
    if [ "${m3_release_iwad_status}" -eq 0 ]; then
        printf 'PASS: optional M3-07 RI04 E1M1/E1M2/E4M1 integration exits with 0\n'
    else
        printf 'FAIL: optional M3-07 RI04 integration exits with %s\n' "${m3_release_iwad_status}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${m3_release_iwad_output}" | grep -Eq -- '^RESULT: PASS'; then
        printf 'PASS: optional M3-07 RI04 reports PASS\n'
    else
        printf 'FAIL: optional M3-07 RI04 did not report PASS\n%s\n' "${m3_release_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${m3_release_iwad_output}" | grep -q -- 'Cases: 1, assertions: 149, failures: 0'; then
        printf 'PASS: M3-07 RI04 runs 1 case/149 assertions/0 failures\n'
    else
        printf 'FAIL: M3-07 RI04 case/assertion totals differ\n%s\n' "${m3_release_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${m3_release_iwad_output}" |
        grep -q -- 'known Ultimate Doom 1.9ud local identity 12408292 bytes/MD5 observed'; then
        printf 'PASS: M3-07 RI04 observed the known owner IWAD identity\n'
    else
        printf 'FAIL: M3-07 RI04 known IWAD identity observation missing\n%s\n' "${m3_release_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    for map_name in E1M1 E1M2 E4M1; do
        CHECKS=$((CHECKS + 1))
        if printf '%s\n' "${m3_release_iwad_output}" |
            grep -q -- "${map_name} transactional textured frame"; then
            printf 'PASS: optional M3-07 actually rendered %s textured frame\n' "${map_name}"
        else
            printf 'FAIL: optional M3-07 %s textured frame measurement missing\n%s\n' "${map_name}" "${m3_release_iwad_output}" >&2
            FAILURES=$((FAILURES + 1))
        fi
    done
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${m3_release_iwad_output}" | grep -q -- 'E1M1 observed textured hash (NOT LOCKED): 183BA53FCECECBC8'; then
        printf 'PASS: M3-07 E1M1 observed textured hash remains 183BA53FCECECBC8\n'
    else
        printf 'FAIL: M3-07 E1M1 observed textured hash changed or missing\n%s\n' "${m3_release_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${m3_release_iwad_output}" | grep -q -- 'E1M2 observed textured hash (NOT LOCKED): 835A0339A38B190E'; then
        printf 'PASS: M3-07 E1M2 observed textured hash remains 835A0339A38B190E\n'
    else
        printf 'FAIL: M3-07 E1M2 observed textured hash changed or missing\n%s\n' "${m3_release_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${m3_release_iwad_output}" | grep -q -- 'E4M1 observed textured hash (NOT LOCKED): 03B5C8CFA517FC7E'; then
        printf 'PASS: M3-07 E4M1 observed textured hash remains 03B5C8CFA517FC7E\n'
    else
        printf 'FAIL: M3-07 E4M1 observed textured hash changed or missing\n%s\n' "${m3_release_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${m3_release_iwad_output}" |
        grep -q -- 'E1M1 independent raw-PATCH composition equals production for 6 bounded textures (0 pixel/mask/mask-width mismatch)'; then
        printf 'PASS: M3-07 E1M1 independent raw composition sampled six textures with zero mismatch\n'
    else
        printf 'FAIL: M3-07 E1M1 independent raw composition measurement missing\n%s\n' "${m3_release_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${m3_release_iwad_output}" |
        grep -q -- 'E1M2 independent raw-PATCH composition equals production for 6 bounded textures (0 pixel/mask/mask-width mismatch)'; then
        printf 'PASS: M3-07 E1M2 independent raw composition sampled six textures with zero mismatch\n'
    else
        printf 'FAIL: M3-07 E1M2 independent raw composition measurement missing\n%s\n' "${m3_release_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${m3_release_iwad_output}" |
        grep -q -- 'E4M1 independent raw-PATCH composition equals production for 4 bounded textures (0 pixel/mask/mask-width mismatch)'; then
        printf 'PASS: M3-07 E4M1 independent raw composition sampled four textures with zero mismatch\n'
    else
        printf 'FAIL: M3-07 E4M1 independent raw composition measurement missing\n%s\n' "${m3_release_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    for map_name in E1M1 E1M2 E4M1; do
        CHECKS=$((CHECKS + 1))
        if printf '%s\n' "${m3_release_iwad_output}" |
            grep -q -- "${map_name} independent raw COLORMAP mismatches: tables 0, texels 0"; then
            printf 'PASS: M3-07 %s raw COLORMAP is exhaustively identical\n' "${map_name}"
        else
            printf 'FAIL: M3-07 %s raw COLORMAP mismatch measurement missing\n%s\n' "${map_name}" "${m3_release_iwad_output}" >&2
            FAILURES=$((FAILURES + 1))
        fi
    done
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${m3_release_iwad_output}" |
        grep -q -- 'E1M1 frame-pixel independent sample NOT RUN: no safe first-span one-sided middle (reason 3)'; then
        printf 'PASS: M3-07 E1M1 bounded frame-pixel oracle honestly NOT RUN with reason 3\n'
    else
        printf 'FAIL: M3-07 E1M1 bounded frame-pixel NOT RUN disclosure missing\n%s\n' "${m3_release_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${m3_release_iwad_output}" |
        grep -q -- 'E1M2 independent first-span middle pixel samples matched 1, mismatches 0'; then
        printf 'PASS: M3-07 E1M2 bounded first-span pixel equals target\n'
    else
        printf 'FAIL: M3-07 E1M2 bounded first-span pixel measurement missing\n%s\n' "${m3_release_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${m3_release_iwad_output}" |
        grep -q -- 'E4M1 independent first-span middle pixel samples matched 1, mismatches 0'; then
        printf 'PASS: M3-07 E4M1 bounded first-span pixel equals target\n'
    else
        printf 'FAIL: M3-07 E4M1 bounded first-span pixel measurement missing\n%s\n' "${m3_release_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${m3_release_iwad_output}" |
        grep -q -- 'residual reference gap: whole clipped-span chronology'; then
        printf 'PASS: M3-07 RI04 reports the residual full-C-frame comparison gap\n'
    else
        printf 'FAIL: M3-07 RI04 residual reference gap disclosure missing\n%s\n' "${m3_release_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${m3_release_iwad_output}" | grep -Eq -- 'owner IWAD remains unchanged'; then
        printf 'PASS: optional M3-07 owner IWAD read-only unchanged\n'
    else
        printf 'FAIL: optional M3-07 owner IWAD unchanged verification missing\n%s\n' "${m3_release_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
fi

printf '\n== M3-07 wall-only frame benchmark build ==\n'
run_build --check --m3-release-benchmark
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3-07 frame benchmark syntax check exits with 0\n'
else
    printf 'FAIL: M3-07 frame benchmark syntax check exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-07 frame benchmark syntax check failed.\n' >&2
    exit 1
fi

run_build --m3-release-benchmark
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M3-07 frame benchmark build exits with 0\n'
else
    printf 'FAIL: M3-07 frame benchmark build exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-07 frame benchmark build failed.\n' >&2
    exit 1
fi

CHECKS=$((CHECKS + 1))
if [ -f "${M3_RELEASE_BENCHMARK_BIN}" ]; then
    printf 'PASS: M3-07 frame benchmark output exists: %s\n' "${M3_RELEASE_BENCHMARK_BIN}"
else
    printf 'FAIL: M3-07 frame benchmark output missing: %s\n' "${M3_RELEASE_BENCHMARK_BIN}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M3-07 frame benchmark output missing.\n' >&2
    exit 1
fi

printf '\n== M3-07 wall-only frame benchmark (BEN01) ==\n'
m3_release_benchmark_output="$("${M3_RELEASE_BENCHMARK_BIN}" 2>&1)"
m3_release_benchmark_status=$?
CHECKS=$((CHECKS + 1))
if [ "${m3_release_benchmark_status}" -eq 0 ]; then
    printf 'PASS: M3-07 BEN01 frame benchmark exits with 0\n'
else
    printf 'FAIL: M3-07 BEN01 frame benchmark exits with %s\n' "${m3_release_benchmark_status}" >&2
    FAILURES=$((FAILURES + 1))
fi
CHECKS=$((CHECKS + 1))
if printf '%s\n' "${m3_release_benchmark_output}" | grep -Eq -- '^RESULT: PASS'; then
    printf 'PASS: M3-07 BEN01 reports PASS\n'
else
    printf 'FAIL: M3-07 BEN01 did not report PASS\n%s\n' "${m3_release_benchmark_output}" >&2
    FAILURES=$((FAILURES + 1))
fi
CHECKS=$((CHECKS + 1))
if printf '%s\n' "${m3_release_benchmark_output}" | grep -q -- 'Cases: 1, assertions: 67, failures: 0'; then
    printf 'PASS: M3-07 BEN01 runs 1 case/67 assertions/0 failures\n'
else
    printf 'FAIL: M3-07 BEN01 case/assertion totals differ\n%s\n' "${m3_release_benchmark_output}" >&2
    FAILURES=$((FAILURES + 1))
fi
CHECKS=$((CHECKS + 1))
if printf '%s\n' "${m3_release_benchmark_output}" | grep -q -- 'clock frequency 10000000 ticks/s, resolution 1 us'; then
    printf 'PASS: M3-07 BEN01 uses verified Windows QPC 10 MHz/1 us clock\n'
else
    printf 'FAIL: M3-07 BEN01 clock measurement missing\n%s\n' "${m3_release_benchmark_output}" >&2
    FAILURES=$((FAILURES + 1))
fi
for marker in 'cold end-to-end wall preview: cycles 2 warmup' 'warm textured frame-only: cycles 20 warmup' 'warm debug-colour frame-only: cycles 10 warmup'; do
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${m3_release_benchmark_output}" | grep -q -- "${marker}"; then
        printf 'PASS: M3-07 BEN01 recorded %s\n' "${marker}"
    else
        printf 'FAIL: M3-07 BEN01 cycle-count marker missing: %s\n%s\n' "${marker}" "${m3_release_benchmark_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
done
CHECKS=$((CHECKS + 1))
if printf '%s\n' "${m3_release_benchmark_output}" |
    grep -q -- 'allocations: warm total 13 observed fixture budget 13; compose 3 unique'; then
    printf 'PASS: M3-07 BEN01 observed fixed pre-column allocation/composition counters\n'
else
    printf 'FAIL: M3-07 BEN01 allocation/composition printout missing\n%s\n' "${m3_release_benchmark_output}" >&2
    FAILURES=$((FAILURES + 1))
fi
CHECKS=$((CHECKS + 1))
if printf '%s\n' "${m3_release_benchmark_output}" |
    grep -q -- 'No WADReadLump/AllocateMemory/TextureCompose appears in the per-column'; then
    printf 'PASS: M3-07 BEN01 reports the static per-column draw-path audit\n'
else
    printf 'FAIL: M3-07 BEN01 static per-column audit line missing\n%s\n' "${m3_release_benchmark_output}" >&2
    FAILURES=$((FAILURES + 1))
fi

printf '\n== M4-01 visplane/real-flat unit test build ==\n'
run_build --check --plane-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M4-01 plane unit test syntax check exits with 0\n'
else
    printf 'FAIL: M4-01 plane unit test syntax check exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M4-01 plane unit test syntax check failed.\n' >&2
    exit 1
fi
run_build --plane-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M4-01 plane unit test build exits with 0\n'
else
    printf 'FAIL: M4-01 plane unit test build exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M4-01 plane unit test build failed.\n' >&2
    exit 1
fi
CHECKS=$((CHECKS + 1))
if [ -f "${PLANE_TEST_BIN}" ]; then
    printf 'PASS: M4-01 plane unit test output exists: %s\n' "${PLANE_TEST_BIN}"
else
    printf 'FAIL: M4-01 plane unit test output missing: %s\n' "${PLANE_TEST_BIN}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M4-01 plane unit test output missing.\n' >&2
    exit 1
fi

printf '\n== M4-01 visplane/real-flat unit tests (PL01-PL60) ==\n'
plane_unit_output="$("${PLANE_TEST_BIN}" 2>&1)"
plane_unit_status=$?
CHECKS=$((CHECKS + 1))
if [ "${plane_unit_status}" -eq 0 ]; then
    printf 'PASS: synthetic M4-01 plane unit tests exit with 0\n'
else
    printf 'FAIL: synthetic M4-01 plane unit tests exit with %s\n' "${plane_unit_status}" >&2
    FAILURES=$((FAILURES + 1))
fi
CHECKS=$((CHECKS + 1))
if printf '%s\n' "${plane_unit_output}" | grep -Eq -- '^RESULT: PASS'; then
    printf 'PASS: M4-01 PL01-PL60 reports PASS\n'
else
    printf 'FAIL: M4-01 plane unit suite did not report PASS\n%s\n' "${plane_unit_output}" >&2
    FAILURES=$((FAILURES + 1))
fi
CHECKS=$((CHECKS + 1))
if printf '%s\n' "${plane_unit_output}" | grep -q -- 'Cases: 60, assertions: 211, failures: 0'; then
    printf 'PASS: M4-01 unit suite runs 60 cases/211 assertions/0 failures\n'
else
    printf 'FAIL: M4-01 plane unit case/assertion totals differ\n%s\n' "${plane_unit_output}" >&2
    FAILURES=$((FAILURES + 1))
fi
for marker in 'CASE PL01:' 'CASE PL60:'; do
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${plane_unit_output}" | grep -q -- "${marker}"; then
        printf 'PASS: M4-01 unit suite actually executed %s\n' "${marker}"
    else
        printf 'FAIL: M4-01 plane unit execution marker %s missing\n%s\n' "${marker}" "${plane_unit_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
done

printf '\n== M4-01 synthetic combined wall+flat integration build ==\n'
run_build --check --plane-integration-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M4-01 synthetic plane integration syntax check exits with 0\n'
else
    printf 'FAIL: M4-01 synthetic plane integration syntax check exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M4-01 synthetic plane integration syntax check failed.\n' >&2
    exit 1
fi
run_build --plane-integration-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M4-01 synthetic plane integration build exits with 0\n'
else
    printf 'FAIL: M4-01 synthetic plane integration build exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M4-01 synthetic plane integration build failed.\n' >&2
    exit 1
fi
CHECKS=$((CHECKS + 1))
if [ -f "${PLANE_INTEGRATION_TEST_BIN}" ]; then
    printf 'PASS: M4-01 synthetic plane integration output exists: %s\n' "${PLANE_INTEGRATION_TEST_BIN}"
else
    printf 'FAIL: M4-01 synthetic plane integration output missing: %s\n' "${PLANE_INTEGRATION_TEST_BIN}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M4-01 synthetic plane integration output missing.\n' >&2
    exit 1
fi

printf '\n== M4-01 synthetic combined wall+flat integration tests (PI01-PI03) ==\n'
plane_integration_output="$("${PLANE_INTEGRATION_TEST_BIN}" 2>&1)"
plane_integration_status=$?
CHECKS=$((CHECKS + 1))
if [ "${plane_integration_status}" -eq 0 ]; then
    printf 'PASS: synthetic M4-01 plane integration tests exit with 0\n'
else
    printf 'FAIL: synthetic M4-01 plane integration tests exit with %s\n' "${plane_integration_status}" >&2
    FAILURES=$((FAILURES + 1))
fi
CHECKS=$((CHECKS + 1))
if printf '%s\n' "${plane_integration_output}" | grep -Eq -- '^RESULT: PASS'; then
    printf 'PASS: M4-01 PI01-PI03 reports PASS\n'
else
    printf 'FAIL: M4-01 synthetic plane integration did not report PASS\n%s\n' "${plane_integration_output}" >&2
    FAILURES=$((FAILURES + 1))
fi
CHECKS=$((CHECKS + 1))
if printf '%s\n' "${plane_integration_output}" | grep -q -- 'Cases: 3, assertions: 76, failures: 0'; then
    printf 'PASS: M4-01 synthetic integration runs 3 cases/76 assertions/0 failures\n'
else
    printf 'FAIL: M4-01 synthetic integration case/assertion totals differ\n%s\n' "${plane_integration_output}" >&2
    FAILURES=$((FAILURES + 1))
fi
for marker in 'CASE PI01:' 'CASE PI02:' 'CASE PI03:'; do
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${plane_integration_output}" | grep -q -- "${marker}"; then
        printf 'PASS: M4-01 synthetic integration actually executed %s\n' "${marker}"
    else
        printf 'FAIL: M4-01 synthetic integration execution marker %s missing\n%s\n' "${marker}" "${plane_integration_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
done

printf '\n== M4-01 optional IWAD combined walls+flats integration build ==\n'
run_build --check --plane-iwad-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M4-01 optional IWAD plane integration syntax check exits with 0\n'
else
    printf 'FAIL: M4-01 optional IWAD plane integration syntax check exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M4-01 optional IWAD plane integration syntax check failed.\n' >&2
    exit 1
fi
run_build --plane-iwad-test
CHECKS=$((CHECKS + 1))
if [ "${LAST_STATUS}" -eq 0 ]; then
    printf 'PASS: M4-01 optional IWAD plane integration build exits with 0\n'
else
    printf 'FAIL: M4-01 optional IWAD plane integration build exits with %s\n' "${LAST_STATUS}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M4-01 optional IWAD plane integration build failed.\n' >&2
    exit 1
fi
CHECKS=$((CHECKS + 1))
if [ -f "${PLANE_IWAD_TEST_BIN}" ]; then
    printf 'PASS: M4-01 optional IWAD plane integration output exists: %s\n' "${PLANE_IWAD_TEST_BIN}"
else
    printf 'FAIL: M4-01 optional IWAD plane integration output missing: %s\n' "${PLANE_IWAD_TEST_BIN}" >&2
    FAILURES=$((FAILURES + 1))
    printf 'Aborting: M4-01 optional IWAD plane integration output missing.\n' >&2
    exit 1
fi

printf '\n== M4-01 optional IWAD combined walls+flats tests (PI04) ==\n'
if [ -z "${IWAD_PATH}" ]; then
    plane_iwad_output="$("${PLANE_IWAD_TEST_BIN}" 2>&1)"
    plane_iwad_status=$?
    CHECKS=$((CHECKS + 1))
    if [ "${plane_iwad_status}" -eq 0 ]; then
        printf 'PASS: optional M4-01 PI04 tests exit with 0 without a WAD path\n'
    else
        printf 'FAIL: optional M4-01 PI04 tests exit with %s\n' "${plane_iwad_status}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${plane_iwad_output}" | grep -q -- 'NOT RUN'; then
        printf 'PASS: optional M4-01 PI04 tests report NOT RUN without a path\n'
    else
        printf 'FAIL: optional M4-01 PI04 tests did not report NOT RUN\n%s\n' "${plane_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${plane_iwad_output}" | grep -q -- 'Cases: 0, assertions: 0, failures: 0'; then
        printf 'PASS: optional M4-01 PI04 no-argument mode is clean\n'
    else
        printf 'FAIL: optional M4-01 PI04 no-argument totals differ\n%s\n' "${plane_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
else
    CHECKS=$((CHECKS + 1))
    if [ -f "${IWAD_PATH}" ]; then
        printf 'PASS: explicit owner IWAD path exists for M4-01\n'
    else
        printf 'FAIL: explicit owner IWAD path does not exist for M4-01\n' >&2
        FAILURES=$((FAILURES + 1))
    fi
    plane_iwad_output="$("${PLANE_IWAD_TEST_BIN}" "${IWAD_PATH}" 2>&1)"
    plane_iwad_status=$?
    CHECKS=$((CHECKS + 1))
    if [ "${plane_iwad_status}" -eq 0 ]; then
        printf 'PASS: optional M4-01 PI04 E1M1/E1M2/E4M1 integration exits with 0\n'
    else
        printf 'FAIL: optional M4-01 PI04 integration exits with %s\n' "${plane_iwad_status}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${plane_iwad_output}" | grep -Eq -- '^RESULT: PASS'; then
        printf 'PASS: optional M4-01 PI04 reports PASS\n'
    else
        printf 'FAIL: optional M4-01 PI04 did not report PASS\n%s\n' "${plane_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${plane_iwad_output}" | grep -q -- 'Cases: 1, assertions: 150, failures: 0'; then
        printf 'PASS: M4-01 PI04 runs 1 case/150 assertions/0 failures\n'
    else
        printf 'FAIL: M4-01 PI04 case/assertion totals differ\n%s\n' "${plane_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${plane_iwad_output}" | grep -Eq -- 'matches known Ultimate Doom 1\.9ud identification 1'; then
        printf 'PASS: M4-01 PI04 observed the known owner IWAD identity\n'
    else
        printf 'FAIL: M4-01 PI04 known owner IWAD identity disclosure missing\n%s\n' "${plane_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    for map_name in E1M1 E1M2 E4M1; do
        CHECKS=$((CHECKS + 1))
        if printf '%s\n' "${plane_iwad_output}" |
            grep -q -- "${map_name} new combined wall+flat frame #1 succeeds"; then
            printf 'PASS: optional M4-01 actually rendered %s combined frame\n' "${map_name}"
        else
            printf 'FAIL: optional M4-01 %s combined frame measurement missing\n%s\n' "${map_name}" "${plane_iwad_output}" >&2
            FAILURES=$((FAILURES + 1))
        fi
        CHECKS=$((CHECKS + 1))
        if printf '%s\n' "${plane_iwad_output}" |
            grep -q -- "${map_name} frozen M3-05 debug frame hash"; then
            printf 'PASS: optional M4-01 %s frozen M3-05 debug hash preserved\n' "${map_name}"
        else
            printf 'FAIL: optional M4-01 %s M3-05 debug preservation missing\n%s\n' "${map_name}" "${plane_iwad_output}" >&2
            FAILURES=$((FAILURES + 1))
        fi
    done
    for map_name in E1M1 E1M2; do
        CHECKS=$((CHECKS + 1))
        if printf '%s\n' "${plane_iwad_output}" |
            grep -q -- "${map_name} real FlatLoad 64x64 floor/ceiling pixels present"; then
            printf 'PASS: optional M4-01 %s real flats visibly present\n' "${map_name}"
        else
            printf 'FAIL: optional M4-01 %s real flat pixel evidence missing\n%s\n' "${map_name}" "${plane_iwad_output}" >&2
            FAILURES=$((FAILURES + 1))
        fi
    done
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${plane_iwad_output}" | grep -q -- 'repeat combined full 64,000-byte frame identical'; then
        printf 'PASS: optional M4-01 combined frames repeat byte-for-byte\n'
    else
        printf 'FAIL: optional M4-01 combined repeat measurement missing\n%s\n' "${plane_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
    CHECKS=$((CHECKS + 1))
    if printf '%s\n' "${plane_iwad_output}" | grep -Eq -- 'owner IWAD MD5 fingerprint unchanged after read-only pass'; then
        printf 'PASS: optional M4-01 owner IWAD read-only MD5 unchanged\n'
    else
        printf 'FAIL: optional M4-01 owner IWAD unchanged verification missing\n%s\n' "${plane_iwad_output}" >&2
        FAILURES=$((FAILURES + 1))
    fi
fi

printf '\n== Smoke tests ==\n'

check_case '--version exits with 0 and prints DoomPB 0.3.0' 0 '^DoomPB 0\.3\.0$' --version
check_case '--help exits with 0 and prints usage' 0 '^Usage:' --help

# --help also has to mention both options; check that separately to keep the
# helper above readable.
CHECKS=$((CHECKS + 1))
help_output="$("${BIN}" --help 2>&1)"
if printf '%s\n' "${help_output}" | grep -q -- '--version' \
    && printf '%s\n' "${help_output}" | grep -q -- '--help'; then
    printf 'PASS: --help documents --help and --version\n'
else
    printf 'FAIL: --help does not document both options\n' >&2
    FAILURES=$((FAILURES + 1))
fi

CHECKS=$((CHECKS + 1))
if printf '%s\n' "${help_output}" | grep -q -- '--show-planes'; then
    printf 'PASS: --help documents the M4-01 --show-planes preview\n'
else
    printf 'FAIL: --help does not document --show-planes\n' >&2
    FAILURES=$((FAILURES + 1))
fi

check_case 'startup without arguments exits with 0' 0 'not implemented'
check_case 'unknown option exits with 2' 2 'unknown option' --definitely-not-an-option
check_case 'too many arguments exits with 2' 2 '' --version extra
check_case '--lump-info without a name exits with 2' 2 '' --lump-info
check_case 'missing WAD for --lump-info exits with 1' 1 '' --iwad definitely-missing-doompb.wad --lump-info PLAYPAL
check_case '--dump-info with --lump-info exits with 2' 2 '' --dump-info --lump-info PLAYPAL
check_case '--show-title without --iwad exits with 2' 2 '' --show-title
check_case 'missing WAD for --show-title exits with 1' 1 '' --iwad definitely-missing-doompb.wad --show-title
check_case '--dump-info with --show-title exits with 2' 2 '' --dump-info --show-title
check_case '--show-planes without --iwad exits with 2' 2 'requires' --show-planes
check_case '--show-planes without a map name exits with 2' 2 'requires a map name' --iwad definitely-missing-doompb.wad --show-planes
check_case 'missing WAD for --show-planes exits with 1' 1 'Cannot open WAD' --iwad definitely-missing-doompb.wad --show-planes E1M1
check_case '--show-planes with --show-walls exits with 2' 2 'may be used' --show-planes E1M1 --show-walls E1M1
check_case 'duplicate --show-planes exits with 2' 2 'duplicate' --show-planes E1M1 --show-planes E1M2
check_case 'extra --show-planes argument exits with 2' 2 'unknown option' --show-planes E1M1 extra

if [ -n "${IWAD_PATH}" ] && [ -f "${IWAD_PATH}" ]; then
    printf '\n== Optional IWAD CLI map-info regression ==\n'
    for map_name in E1M1 E1M2 E4M1; do
        map_info_output="$("${BIN}" --iwad "${IWAD_PATH}" --map-info "${map_name}" 2>&1)"
        map_info_status=$?
        CHECKS=$((CHECKS + 1))
        if [ "${map_info_status}" -eq 0 ]; then
            printf 'PASS: --map-info %s exits with 0\n' "${map_name}"
        else
            printf 'FAIL: --map-info %s exits with %s\n' "${map_name}" "${map_info_status}" >&2
            FAILURES=$((FAILURES + 1))
        fi
        CHECKS=$((CHECKS + 1))
        if printf '%s\n' "${map_info_output}" | grep -Eq -- "^Map: ${map_name}$"; then
            printf 'PASS: --map-info %s prints canonical map identity\n' "${map_name}"
        else
            printf 'FAIL: --map-info %s map identity missing\n%s\n' "${map_name}" "${map_info_output}" >&2
            FAILURES=$((FAILURES + 1))
        fi
        CHECKS=$((CHECKS + 1))
        if printf '%s\n' "${map_info_output}" | grep -q -- '^BSP root:'; then
            printf 'PASS: --map-info %s reports its M2 BSP root\n' "${map_name}"
        else
            printf 'FAIL: --map-info %s BSP-root line missing\n' "${map_name}" >&2
            FAILURES=$((FAILURES + 1))
        fi
        CHECKS=$((CHECKS + 1))
        if printf '%s\n' "${map_info_output}" | grep -q -- '^Validation: OK'; then
            printf 'PASS: --map-info %s validates the level\n' "${map_name}"
        else
            printf 'FAIL: --map-info %s validation line missing\n' "${map_name}" >&2
            FAILURES=$((FAILURES + 1))
        fi
    done
fi

printf '\n'
if [ "${FAILURES}" -ne 0 ]; then
    printf '%s of %s checks failed.\n' "${FAILURES}" "${CHECKS}" >&2
    exit 1
fi

printf 'All %s checks passed.\n' "${CHECKS}"
exit 0
