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

.PARAMETER ResourceTest
    Build the synthetic COLORMAP/PNAMES unit-test program
    (tests/unit/wad_resource_tests.pb) instead of the main executable.

.PARAMETER TextureDefTest
    Build the synthetic TEXTURE1/TEXTURE2 definition unit-test program
    (tests/unit/wad_texture_defs_tests.pb) instead of the main executable.

.PARAMETER CompositeTest
    Build the synthetic composite wall-texture unit-test program
    (tests/unit/wad_composite_tests.pb) instead of the main executable.

.PARAMETER FlatSpriteTest
    Build the synthetic flat/sprite namespace unit-test program
    (tests/unit/wad_flat_sprite_tests.pb) instead of the main executable.

.PARAMETER MapTypesTest
    Build the synthetic vanilla map binary unit-test program
    (tests/unit/wad_map_types_tests.pb) instead of the main executable.

.PARAMETER MapLoaderTest
    Build the synthetic map loader/validation unit-test program
    (tests/unit/wad_map_loader_tests.pb) instead of the main executable.

.PARAMETER IntegrationTest
    Build the M2 end-to-end resource/map integration test program
    (tests/integration/m2_release_tests.pb) instead of the main executable.

.PARAMETER FixedTest
    Build the M3-01 fixed-point math unit test program
    (tests/unit/fixed_math_tests.pb) instead of the main executable.

.PARAMETER FixedIwadTest
    Build the optional M3-01 real-IWAD fixed-point integration test program
    (tests/integration/m3_fixed_iwad_tests.pb) instead of the main executable.

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

.EXAMPLE
    ./scripts/build.ps1 -ResourceTest

.EXAMPLE
    ./scripts/build.ps1 -TextureDefTest

.EXAMPLE
    ./scripts/build.ps1 -CompositeTest

.EXAMPLE
    ./scripts/build.ps1 -FlatSpriteTest

.EXAMPLE
    ./scripts/build.ps1 -MapTypesTest

.EXAMPLE
    ./scripts/build.ps1 -MapLoaderTest

.EXAMPLE
    ./scripts/build.ps1 -IntegrationTest

.EXAMPLE
    ./scripts/build.ps1 -FixedTest

.EXAMPLE
    ./scripts/build.ps1 -FixedIwadTest
#>
[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$Test,
    [switch]$LumpTest,
    [switch]$GraphicsTest,
    [switch]$DisplayTest,
    [switch]$ResourceTest,
    [switch]$TextureDefTest,
    [switch]$CompositeTest,
    [switch]$FlatSpriteTest,
    [switch]$MapTypesTest,
    [switch]$MapLoaderTest,
    [switch]$IntegrationTest,
    [switch]$FixedTest,
    [switch]$FixedIwadTest,
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
if ($ResourceTest) { $selectedTargets++ }
if ($TextureDefTest) { $selectedTargets++ }
if ($CompositeTest) { $selectedTargets++ }
if ($FlatSpriteTest) { $selectedTargets++ }
if ($MapTypesTest) { $selectedTargets++ }
if ($MapLoaderTest) { $selectedTargets++ }
if ($IntegrationTest) { $selectedTargets++ }
if ($FixedTest) { $selectedTargets++ }
if ($FixedIwadTest) { $selectedTargets++ }
if ($selectedTargets -gt 1) {
    Write-Host 'error: test targets select different programs; choose one.' -ForegroundColor Red
    exit 1
}

if ($FixedIwadTest) {
    $sourceFile = Join-Path $repoRoot 'tests\integration\m3_fixed_iwad_tests.pb'
    $outputFile = Join-Path $buildDir 'DoomPB-M3FixedIwadTests.exe'
} elseif ($FixedTest) {
    $sourceFile = Join-Path $repoRoot 'tests\unit\fixed_math_tests.pb'
    $outputFile = Join-Path $buildDir 'DoomPB-FixedMathTests.exe'
} elseif ($IntegrationTest) {
    $sourceFile = Join-Path $repoRoot 'tests\integration\m2_release_tests.pb'
    $outputFile = Join-Path $buildDir 'DoomPB-M2IntegrationTests.exe'
} elseif ($MapLoaderTest) {
    $sourceFile = Join-Path $repoRoot 'tests\unit\wad_map_loader_tests.pb'
    $outputFile = Join-Path $buildDir 'DoomPB-WadMapLoaderTests.exe'
} elseif ($MapTypesTest) {
    $sourceFile = Join-Path $repoRoot 'tests\unit\wad_map_types_tests.pb'
    $outputFile = Join-Path $buildDir 'DoomPB-WadMapTypesTests.exe'
} elseif ($FlatSpriteTest) {
    $sourceFile = Join-Path $repoRoot 'tests\unit\wad_flat_sprite_tests.pb'
    $outputFile = Join-Path $buildDir 'DoomPB-WadFlatSpriteTests.exe'
} elseif ($CompositeTest) {
    $sourceFile = Join-Path $repoRoot 'tests\unit\wad_composite_tests.pb'
    $outputFile = Join-Path $buildDir 'DoomPB-WadCompositeTests.exe'
} elseif ($TextureDefTest) {
    $sourceFile = Join-Path $repoRoot 'tests\unit\wad_texture_defs_tests.pb'
    $outputFile = Join-Path $buildDir 'DoomPB-WadTextureDefsTests.exe'
} elseif ($ResourceTest) {
    $sourceFile = Join-Path $repoRoot 'tests\unit\wad_resource_tests.pb'
    $outputFile = Join-Path $buildDir 'DoomPB-WadResourceTests.exe'
} elseif ($DisplayTest) {
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
