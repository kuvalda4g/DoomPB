#!/usr/bin/env bash
#
# Runs the DoomPB verification suite on Linux/Unix.
#
# Performs a real PureBasic syntax check, a real build, the synthetic WAD
# header/directory and lump lookup/payload unit tests, and smoke tests against
# the produced executable: --version, --help, no-argument startup,
# unknown-option handling and --lump-info argument validation. No commercial
# game data and no display are needed.
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

printf '\n== Smoke tests ==\n'

check_case '--version exits with 0 and prints DoomPB 0.0.1' 0 '^DoomPB 0\.0\.1$' --version
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

printf '\n'
if [ "${FAILURES}" -ne 0 ]; then
    printf '%s of %s checks failed.\n' "${FAILURES}" "${CHECKS}" >&2
    exit 1
fi

printf 'All %s checks passed.\n' "${CHECKS}"
exit 0
