#!/usr/bin/env bash
#
# Runs the DoomPB verification suite on Linux/Unix.
#
# Performs a real PureBasic syntax check, a real build, the synthetic WAD
# header/directory, lump lookup/payload, PLAYPAL/patch, framebuffer/presentation,
# COLORMAP/PNAMES, TEXTURE1/TEXTURE2 definition, composite wall-texture,
# flat/sprite namespace, vanilla map binary and map loader/validation unit
# tests, and smoke tests
# against the produced executable: --version, --help, no-argument startup,
# unknown-option handling, --lump-info argument validation and nonblocking
# --show-title failures. No commercial game data and no display are needed.
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

printf '\n== Smoke tests ==\n'

check_case '--version exits with 0 and prints DoomPB 0.1.0' 0 '^DoomPB 0\.1\.0$' --version
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

check_case 'startup without arguments exits with 0' 0 'not implemented'
check_case 'unknown option exits with 2' 2 'unknown option' --definitely-not-an-option
check_case 'too many arguments exits with 2' 2 '' --version extra
check_case '--lump-info without a name exits with 2' 2 '' --lump-info
check_case 'missing WAD for --lump-info exits with 1' 1 '' --iwad definitely-missing-doompb.wad --lump-info PLAYPAL
check_case '--dump-info with --lump-info exits with 2' 2 '' --dump-info --lump-info PLAYPAL
check_case '--show-title without --iwad exits with 2' 2 '' --show-title
check_case 'missing WAD for --show-title exits with 1' 1 '' --iwad definitely-missing-doompb.wad --show-title
check_case '--dump-info with --show-title exits with 2' 2 '' --dump-info --show-title

printf '\n'
if [ "${FAILURES}" -ne 0 ]; then
    printf '%s of %s checks failed.\n' "${FAILURES}" "${CHECKS}" >&2
    exit 1
fi

printf 'All %s checks passed.\n' "${CHECKS}"
exit 0
