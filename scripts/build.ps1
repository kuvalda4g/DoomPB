<#
.SYNOPSIS
    Builds or syntax-checks DoomPB with the PureBasic 6.41 command line compiler.

.DESCRIPTION
    Resolves the compiler from -CompilerPath, then PB_COMPILER, then PATH, then
    the standard PureBasic installation directories. Only repository-relative
    paths are used for sources and outputs, so the script can be started from
    any working directory.

    Exit codes: 0 on success, 1 when the compiler cannot be found or a build
    step fails, otherwise the compiler's own exit code.

.PARAMETER Check
    Run only the PureBasic syntax check; no executable is produced.

.PARAMETER Test
    Build the synthetic WAD header/directory unit-test program
    (tests/unit/wad_header_tests.pb) instead of the main executable.

.PARAMETER LumpTest
    Build the synthetic WAD lookup/payload unit-test program
    (tests/unit/wad_lump_tests.pb) instead of the main executable.

.PARAMETER GraphicsTest
    Build the synthetic PLAYPAL/patch decoder unit-test program
    (tests/unit/wad_graphics_tests.pb) instead of the main executable.

.PARAMETER DisplayTest
    Build the synthetic framebuffer/presentation unit-test program
    (tests/unit/wad_display_tests.pb) instead of the main executable.

.PARAMETER CompilerPath
    Explicit path (or command name) of pbcompiler. Overrides PB_COMPILER and
    automatic discovery.

.EXAMPLE
    ./scripts/build.ps1 -Check

.EXAMPLE
    ./scripts/build.ps1 -Test

.EXAMPLE
    ./scripts/build.ps1 -LumpTest

.EXAMPLE
    ./scripts/build.ps1 -GraphicsTest

.EXAMPLE
    ./scripts/build.ps1 -DisplayTest
#>
[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$Test,
    [switch]$LumpTest,
    [switch]$GraphicsTest,
    [switch]$DisplayTest,
    [string]$CompilerPath = ''
)

$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
$repoRoot  = Split-Path -Parent $scriptDir
$buildDir  = Join-Path $repoRoot 'build'

$selectedTargets = 0
if ($Test) { $selectedTargets++ }
if ($LumpTest) { $selectedTargets++ }
if ($GraphicsTest) { $selectedTargets++ }
if ($DisplayTest) { $selectedTargets++ }
if ($selectedTargets -gt 1) {
    Write-Host 'error: -Test, -LumpTest, -GraphicsTest and -DisplayTest select different programs; choose one.' -ForegroundColor Red
    exit 1
}

if ($DisplayTest) {
    $sourceFile = Join-Path $repoRoot 'tests\unit\wad_display_tests.pb'
    $outputFile = Join-Path $buildDir 'DoomPB-WadDisplayTests.exe'
} elseif ($GraphicsTest) {
    $sourceFile = Join-Path $repoRoot 'tests\unit\wad_graphics_tests.pb'
    $outputFile = Join-Path $buildDir 'DoomPB-WadGraphicsTests.exe'
} elseif ($LumpTest) {
    $sourceFile = Join-Path $repoRoot 'tests\unit\wad_lump_tests.pb'
    $outputFile = Join-Path $buildDir 'DoomPB-WadLumpTests.exe'
} elseif ($Test) {
    $sourceFile = Join-Path $repoRoot 'tests\unit\wad_header_tests.pb'
    $outputFile = Join-Path $buildDir 'DoomPB-WadTests.exe'
} else {
    $sourceFile = Join-Path $repoRoot 'src\DoomPB.pb'
    $outputFile = Join-Path $buildDir 'DoomPB.exe'
}

function Fail {
    param([string]$Message)
    Write-Host "error: $Message" -ForegroundColor Red
    exit 1
}

function Find-PureBasicCompiler {
    param([string]$ExplicitPath)

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        $command = Get-Command $ExplicitPath -ErrorAction SilentlyContinue
        if ($null -ne $command) { return $command.Source }
        if (Test-Path -LiteralPath $ExplicitPath -PathType Leaf) {
            return (Resolve-Path -LiteralPath $ExplicitPath).Path
        }
        Fail "compiler not found at '$ExplicitPath' (see -CompilerPath)."
    }

    if (-not [string]::IsNullOrWhiteSpace($env:PB_COMPILER)) {
        $command = Get-Command $env:PB_COMPILER -ErrorAction SilentlyContinue
        if ($null -ne $command) { return $command.Source }
        if (Test-Path -LiteralPath $env:PB_COMPILER -PathType Leaf) {
            return (Resolve-Path -LiteralPath $env:PB_COMPILER).Path
        }
        Fail "PB_COMPILER is set to '$env:PB_COMPILER', but no compiler exists there."
    }

    foreach ($name in @('pbcompiler.exe', 'pbcompiler')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($null -ne $command) { return $command.Source }
    }

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $candidates += Join-Path $env:ProgramFiles 'PureBasic\Compilers\pbcompiler.exe'
    }
    if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) {
        $candidates += Join-Path ${env:ProgramFiles(x86)} 'PureBasic\Compilers\pbcompiler.exe'
    }
    if (-not [string]::IsNullOrWhiteSpace($env:PUREBASIC_HOME)) {
        $candidates += Join-Path $env:PUREBASIC_HOME 'Compilers\pbcompiler.exe'
    }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }

    Fail 'PureBasic compiler not found. Add pbcompiler to PATH, set PB_COMPILER, or pass -CompilerPath.'
}

if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) {
    Fail "source file not found: $sourceFile"
}

$compiler = Find-PureBasicCompiler -ExplicitPath $CompilerPath
Write-Host "Compiler: $compiler"

# pbcompiler 6.41 exits with status 1 for --version even on success, so the
# version banner is informational only and must not abort the script.
$versionOutput = & $compiler --version 2>&1
Write-Host ($versionOutput -join [Environment]::NewLine)

if ($Check) {
    Write-Host "Syntax check: $sourceFile"
    & $compiler $sourceFile --check
    $status = $LASTEXITCODE
    if ($status -eq 0) {
        Write-Host 'Syntax check passed.'
    } else {
        Write-Host "Syntax check failed (exit code $status)." -ForegroundColor Red
    }
    exit $status
}

New-Item -ItemType Directory -Force -Path $buildDir | Out-Null

Write-Host "Building: $sourceFile -> $outputFile"
& $compiler $sourceFile --console --output $outputFile
$status = $LASTEXITCODE
if ($status -ne 0) {
    Write-Host "Build failed (exit code $status)." -ForegroundColor Red
    exit $status
}
if (-not (Test-Path -LiteralPath $outputFile -PathType Leaf)) {
    Fail "compiler reported success but '$outputFile' does not exist."
}

Write-Host "Build succeeded: $outputFile"
exit 0
