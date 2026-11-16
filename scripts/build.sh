#!/usr/bin/env bash
#
# Builds or syntax-checks DoomPB with the PureBasic 6.41 command line compiler.
#
# Compiler discovery order: PB_COMPILER, PATH, common installation directories.
# Repository paths are resolved relative to this script, so it can be started
# from any working directory.
#
# Exit codes: 0 on success, 1 when the compiler cannot be found or a build step
# fails, 2 for an invalid script argument, otherwise the compiler's own code.

set -u
set -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"
SOURCE_FILE="${REPO_ROOT}/src/DoomPB.pb"
BUILD_DIR="${REPO_ROOT}/build"
OUTPUT_FILE="${BUILD_DIR}/DoomPB"
CHECK_ONLY=0
TEST_BUILD=0
LUMP_TEST_BUILD=0
GRAPHICS_TEST_BUILD=0
DISPLAY_TEST_BUILD=0
RESOURCE_TEST_BUILD=0
TEXTURE_DEF_TEST_BUILD=0
COMPOSITE_TEST_BUILD=0
FLAT_SPRITE_TEST_BUILD=0
MAP_TYPES_TEST_BUILD=0
MAP_LOADER_TEST_BUILD=0
INTEGRATION_TEST_BUILD=0

usage() {
    cat <<'EOF'
Usage: build.sh [--check | --test | --lump-test | --graphics-test | --display-test | --resource-test | --texture-def-test | --composite-test | --flat-sprite-test | --map-types-test | --map-loader-test | --integration-test] [--help]

  (no option)   Syntax-check and build build/DoomPB.
  -k, --check   Run the PureBasic syntax check only.
  -t, --test    Build the WAD header/directory test program instead.
  -l, --lump-test
                Build the WAD lump lookup/payload test program instead.
  -g, --graphics-test
                Build the PLAYPAL/patch decoder test program instead.
  -d, --display-test
                Build the framebuffer/presentation test program instead.
  -r, --resource-test
                Build the COLORMAP/PNAMES decoder test program instead.
  -x, --texture-def-test
                Build the TEXTURE1/TEXTURE2 definition test program instead.
  -c, --composite-test
                Build the composite wall-texture test program instead.
  -f, --flat-sprite-test
                Build the flat/sprite namespace test program instead.
  -m, --map-types-test
                Build the vanilla map binary test program instead.
  -L, --map-loader-test
                Build the map loader/validation test program instead.
  -I, --integration-test
                Build the M2 end-to-end integration test program instead.
  -h, --help    Show this help and exit.

Compiler discovery: PB_COMPILER, then pbcompiler on PATH, then common
installation directories. Set PB_COMPILER to select a specific compiler.
EOF
}

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

find_compiler() {
    if [ -n "${PB_COMPILER:-}" ]; then
        if command -v -- "${PB_COMPILER}" >/dev/null 2>&1; then
            command -v -- "${PB_COMPILER}"
            return 0
        fi
        if [ -x "${PB_COMPILER}" ]; then
            printf '%s\n' "${PB_COMPILER}"
            return 0
        fi
        fail "PB_COMPILER='${PB_COMPILER}' is not an executable file or command."
    fi

    if command -v pbcompiler >/dev/null 2>&1; then
        command -v pbcompiler
        return 0
    fi

    for candidate in \
        /opt/purebasic/compilers/pbcompiler \
        /usr/local/purebasic/compilers/pbcompiler \
        "${HOME:-}/purebasic/compilers/pbcompiler"
    do
        if [ -n "${candidate}" ] && [ -x "${candidate}" ]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done

    fail 'PureBasic compiler not found. Add pbcompiler to PATH or set PB_COMPILER.'
}

while [ $# -gt 0 ]; do
    case "$1" in
        -k|--check)
            CHECK_ONLY=1
            ;;
        -t|--test)
            TEST_BUILD=1
            ;;
        -l|--lump-test)
            LUMP_TEST_BUILD=1
            ;;
        -g|--graphics-test)
            GRAPHICS_TEST_BUILD=1
            ;;
        -d|--display-test)
            DISPLAY_TEST_BUILD=1
            ;;
        -r|--resource-test)
            RESOURCE_TEST_BUILD=1
            ;;
        -x|--texture-def-test)
            TEXTURE_DEF_TEST_BUILD=1
            ;;
        -c|--composite-test)
            COMPOSITE_TEST_BUILD=1
            ;;
        -f|--flat-sprite-test)
            FLAT_SPRITE_TEST_BUILD=1
            ;;
        -m|--map-types-test)
            MAP_TYPES_TEST_BUILD=1
            ;;
        -L|--map-loader-test)
            MAP_LOADER_TEST_BUILD=1
            ;;
        -I|--integration-test)
            INTEGRATION_TEST_BUILD=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'error: unknown argument: %s\n\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

[ -f "${SOURCE_FILE}" ] || fail "source file not found: ${SOURCE_FILE}"

selected_targets=$((TEST_BUILD + LUMP_TEST_BUILD + GRAPHICS_TEST_BUILD + DISPLAY_TEST_BUILD + RESOURCE_TEST_BUILD + TEXTURE_DEF_TEST_BUILD + COMPOSITE_TEST_BUILD + FLAT_SPRITE_TEST_BUILD + MAP_TYPES_TEST_BUILD + MAP_LOADER_TEST_BUILD + INTEGRATION_TEST_BUILD))
if [ "${selected_targets}" -gt 1 ]; then
    fail 'test targets select different programs; choose one.'
fi

if [ "${TEST_BUILD}" -eq 1 ]; then
    SOURCE_FILE="${REPO_ROOT}/tests/unit/wad_header_tests.pb"
    OUTPUT_FILE="${BUILD_DIR}/DoomPB-WadTests"
    [ -f "${SOURCE_FILE}" ] || fail "source file not found: ${SOURCE_FILE}"
fi

if [ "${LUMP_TEST_BUILD}" -eq 1 ]; then
    SOURCE_FILE="${REPO_ROOT}/tests/unit/wad_lump_tests.pb"
    OUTPUT_FILE="${BUILD_DIR}/DoomPB-WadLumpTests"
    [ -f "${SOURCE_FILE}" ] || fail "source file not found: ${SOURCE_FILE}"
fi

if [ "${GRAPHICS_TEST_BUILD}" -eq 1 ]; then
    SOURCE_FILE="${REPO_ROOT}/tests/unit/wad_graphics_tests.pb"
    OUTPUT_FILE="${BUILD_DIR}/DoomPB-WadGraphicsTests"
    [ -f "${SOURCE_FILE}" ] || fail "source file not found: ${SOURCE_FILE}"
fi

if [ "${DISPLAY_TEST_BUILD}" -eq 1 ]; then
    SOURCE_FILE="${REPO_ROOT}/tests/unit/wad_display_tests.pb"
    OUTPUT_FILE="${BUILD_DIR}/DoomPB-WadDisplayTests"
    [ -f "${SOURCE_FILE}" ] || fail "source file not found: ${SOURCE_FILE}"
fi

if [ "${RESOURCE_TEST_BUILD}" -eq 1 ]; then
    SOURCE_FILE="${REPO_ROOT}/tests/unit/wad_resource_tests.pb"
    OUTPUT_FILE="${BUILD_DIR}/DoomPB-WadResourceTests"
    [ -f "${SOURCE_FILE}" ] || fail "source file not found: ${SOURCE_FILE}"
fi

if [ "${TEXTURE_DEF_TEST_BUILD}" -eq 1 ]; then
    SOURCE_FILE="${REPO_ROOT}/tests/unit/wad_texture_defs_tests.pb"
    OUTPUT_FILE="${BUILD_DIR}/DoomPB-WadTextureDefsTests"
    [ -f "${SOURCE_FILE}" ] || fail "source file not found: ${SOURCE_FILE}"
fi

if [ "${COMPOSITE_TEST_BUILD}" -eq 1 ]; then
    SOURCE_FILE="${REPO_ROOT}/tests/unit/wad_composite_tests.pb"
    OUTPUT_FILE="${BUILD_DIR}/DoomPB-WadCompositeTests"
    [ -f "${SOURCE_FILE}" ] || fail "source file not found: ${SOURCE_FILE}"
fi

if [ "${FLAT_SPRITE_TEST_BUILD}" -eq 1 ]; then
    SOURCE_FILE="${REPO_ROOT}/tests/unit/wad_flat_sprite_tests.pb"
    OUTPUT_FILE="${BUILD_DIR}/DoomPB-WadFlatSpriteTests"
    [ -f "${SOURCE_FILE}" ] || fail "source file not found: ${SOURCE_FILE}"
fi

if [ "${MAP_TYPES_TEST_BUILD}" -eq 1 ]; then
    SOURCE_FILE="${REPO_ROOT}/tests/unit/wad_map_types_tests.pb"
    OUTPUT_FILE="${BUILD_DIR}/DoomPB-WadMapTypesTests"
    [ -f "${SOURCE_FILE}" ] || fail "source file not found: ${SOURCE_FILE}"
fi

if [ "${MAP_LOADER_TEST_BUILD}" -eq 1 ]; then
    SOURCE_FILE="${REPO_ROOT}/tests/unit/wad_map_loader_tests.pb"
    OUTPUT_FILE="${BUILD_DIR}/DoomPB-WadMapLoaderTests"
    [ -f "${SOURCE_FILE}" ] || fail "source file not found: ${SOURCE_FILE}"
fi

if [ "${INTEGRATION_TEST_BUILD}" -eq 1 ]; then
    SOURCE_FILE="${REPO_ROOT}/tests/integration/m2_release_tests.pb"
    OUTPUT_FILE="${BUILD_DIR}/DoomPB-M2IntegrationTests"
    [ -f "${SOURCE_FILE}" ] || fail "source file not found: ${SOURCE_FILE}"
fi

COMPILER="$(find_compiler)" || exit 1
printf 'Compiler: %s\n' "${COMPILER}"

# pbcompiler 6.41 returns exit code 1 for --version even on success, so the
# version banner is informational only and must not abort the script.
version_output="$("${COMPILER}" --version 2>&1)"
version_status=$?
printf '%s\n' "${version_output}"
if [ "${version_status}" -ne 0 ]; then
    printf 'note: pbcompiler --version returned %s (known PureBasic 6.41 behaviour).\n' "${version_status}"
fi

if [ "${CHECK_ONLY}" -eq 1 ]; then
    printf 'Syntax check: %s\n' "${SOURCE_FILE}"
    "${COMPILER}" "${SOURCE_FILE}" --check
    status=$?
    if [ "${status}" -eq 0 ]; then
        printf 'Syntax check passed.\n'
    else
        printf 'Syntax check failed (exit code %s).\n' "${status}" >&2
    fi
    exit "${status}"
fi

mkdir -p "${BUILD_DIR}" || fail "cannot create build directory: ${BUILD_DIR}"

printf 'Building: %s -> %s\n' "${SOURCE_FILE}" "${OUTPUT_FILE}"
"${COMPILER}" "${SOURCE_FILE}" --console --output "${OUTPUT_FILE}"
status=$?
if [ "${status}" -ne 0 ]; then
    printf 'Build failed (exit code %s).\n' "${status}" >&2
    exit "${status}"
fi
if [ ! -f "${OUTPUT_FILE}" ]; then
    fail "compiler reported success but '${OUTPUT_FILE}' does not exist."
fi

printf 'Build succeeded: %s\n' "${OUTPUT_FILE}"
exit 0
