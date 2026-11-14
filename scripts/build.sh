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

usage() {
    cat <<'EOF'
Usage: build.sh [--check] [--help]

  (no option)  Syntax-check and build build/DoomPB.
  -k, --check  Run the PureBasic syntax check only.
  -h, --help   Show this help and exit.

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
