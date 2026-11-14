<#
.SYNOPSIS
    Runs the DoomPB verification suite on Windows.

.DESCRIPTION
    Performs a real PureBasic syntax check, a real build, the synthetic WAD
    header/directory, lump lookup/payload and PLAYPAL/patch decoder unit tests,
    and smoke tests against the produced executable: --version, --help,
    no-argument startup, unknown-option handling and --lump-info argument
    validation. No commercial game data and no display are needed.

    Exit code 0 means every check passed; 1 means at least one check failed.

.PARAMETER CompilerPath
    Explicit path (or command name) of pbcompiler, forwarded to build.ps1.

.EXAMPLE
    ./scripts/test.ps1
#>
[CmdletBinding()]
param(
    [string]$CompilerPath = ''
)

$ErrorActionPreference = 'Stop'

$scriptDir   = $PSScriptRoot
$repoRoot    = Split-Path -Parent $scriptDir
$buildScript = Join-Path $scriptDir 'build.ps1'
$exePath     = Join-Path $repoRoot 'build\DoomPB.exe'
$unitTestExe = Join-Path $repoRoot 'build\DoomPB-WadTests.exe'
$lumpTestExe = Join-Path $repoRoot 'build\DoomPB-WadLumpTests.exe'
$graphicsTestExe = Join-Path $repoRoot 'build\DoomPB-WadGraphicsTests.exe'

$script:checks   = 0
$script:failures = 0

function Test-Condition {
    param(
        [bool]$Condition,
        [string]$Description
    )
    $script:checks++
    if ($Condition) {
        Write-Host "PASS: $Description" -ForegroundColor Green
    } else {
        Write-Host "FAIL: $Description" -ForegroundColor Red
        $script:failures++
    }
}

function Invoke-BuildStep {
    param([switch]$Check, [switch]$Test, [switch]$LumpTest, [switch]$GraphicsTest)
    if ([string]::IsNullOrWhiteSpace($CompilerPath)) {
        & $buildScript -Check:$Check -Test:$Test -LumpTest:$LumpTest -GraphicsTest:$GraphicsTest
    } else {
        & $buildScript -Check:$Check -Test:$Test -LumpTest:$LumpTest -GraphicsTest:$GraphicsTest -CompilerPath $CompilerPath
    }
    return $LASTEXITCODE
}

function Invoke-DoomPB {
    param([string[]]$Arguments)
    $output = & $exePath @Arguments 2>&1 | Out-String
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output   = $output
    }
}

Write-Host '== Syntax check =='
$status = Invoke-BuildStep -Check
Test-Condition ($status -eq 0) "PureBasic syntax check exits with 0 (got $status)"
if ($status -ne 0) {
    Write-Host "Aborting: syntax check failed." -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host '== Build =='
$status = Invoke-BuildStep
Test-Condition ($status -eq 0) "PureBasic build exits with 0 (got $status)"
Test-Condition (Test-Path -LiteralPath $exePath -PathType Leaf) "build output exists: $exePath"
if ($status -ne 0 -or -not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
    Write-Host "Aborting: build failed." -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host '== WAD unit test build =='
$status = Invoke-BuildStep -Check -Test
Test-Condition ($status -eq 0) "WAD test syntax check exits with 0 (got $status)"
$status = Invoke-BuildStep -Test
Test-Condition ($status -eq 0) "WAD test build exits with 0 (got $status)"
Test-Condition (Test-Path -LiteralPath $unitTestExe -PathType Leaf) "WAD test output exists: $unitTestExe"
if ($status -ne 0 -or -not (Test-Path -LiteralPath $unitTestExe -PathType Leaf)) {
    Write-Host "Aborting: WAD test build failed." -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host '== WAD lump lookup/payload test build =='
$status = Invoke-BuildStep -Check -LumpTest
Test-Condition ($status -eq 0) "WAD lump test syntax check exits with 0 (got $status)"
$status = Invoke-BuildStep -LumpTest
Test-Condition ($status -eq 0) "WAD lump test build exits with 0 (got $status)"
Test-Condition (Test-Path -LiteralPath $lumpTestExe -PathType Leaf) "WAD lump test output exists: $lumpTestExe"
if ($status -ne 0 -or -not (Test-Path -LiteralPath $lumpTestExe -PathType Leaf)) {
    Write-Host "Aborting: WAD lump test build failed." -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host '== WAD header/directory unit tests =='
& $unitTestExe
$status = $LASTEXITCODE
Test-Condition ($status -eq 0) "synthetic WAD tests exit with 0 (got $status)"

Write-Host ''
Write-Host '== WAD graphics decoder test build =='
$status = Invoke-BuildStep -Check -GraphicsTest
Test-Condition ($status -eq 0) "WAD graphics test syntax check exits with 0 (got $status)"
$status = Invoke-BuildStep -GraphicsTest
Test-Condition ($status -eq 0) "WAD graphics test build exits with 0 (got $status)"
Test-Condition (Test-Path -LiteralPath $graphicsTestExe -PathType Leaf) "WAD graphics test output exists: $graphicsTestExe"
if ($status -ne 0 -or -not (Test-Path -LiteralPath $graphicsTestExe -PathType Leaf)) {
    Write-Host "Aborting: WAD graphics test build failed." -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host '== WAD lump lookup/payload unit tests =='
& $lumpTestExe
$status = $LASTEXITCODE
Test-Condition ($status -eq 0) "synthetic WAD lump tests exit with 0 (got $status)"

Write-Host ''
Write-Host '== WAD PLAYPAL/patch decoder unit tests =='
& $graphicsTestExe
$status = $LASTEXITCODE
Test-Condition ($status -eq 0) "synthetic WAD graphics tests exit with 0 (got $status)"

Write-Host ''
Write-Host '== Smoke tests =='

$result = Invoke-DoomPB -Arguments @('--version')
Test-Condition ($result.ExitCode -eq 0) "--version exits with 0 (got $($result.ExitCode))"
Test-Condition ($result.Output -match '(?m)^DoomPB 0\.0\.1\s*$') "--version prints 'DoomPB 0.0.1' (got: $($result.Output.Trim()))"

$result = Invoke-DoomPB -Arguments @('--help')
Test-Condition ($result.ExitCode -eq 0) "--help exits with 0 (got $($result.ExitCode))"
Test-Condition ($result.Output -match '(?m)^Usage:') "--help prints a usage line"
Test-Condition ($result.Output -match '--version') "--help documents --version"
Test-Condition ($result.Output -match '--help') "--help documents --help"

$result = Invoke-DoomPB -Arguments @()
Test-Condition ($result.ExitCode -eq 0) 'startup without arguments exits with 0'
Test-Condition ($result.Output -match 'not implemented') 'startup without arguments reports the bootstrap status'

$result = Invoke-DoomPB -Arguments @('--definitely-not-an-option')
Test-Condition ($result.ExitCode -eq 2) "unknown option exits with 2 (got $($result.ExitCode))"
Test-Condition ($result.Output -match 'unknown option') 'unknown option produces a diagnostic'

$result = Invoke-DoomPB -Arguments @('--version', 'extra')
Test-Condition ($result.ExitCode -eq 2) "too many arguments exits with 2 (got $($result.ExitCode))"

$result = Invoke-DoomPB -Arguments @('--lump-info')
Test-Condition ($result.ExitCode -eq 2) "--lump-info without a name exits with 2 (got $($result.ExitCode))"

$result = Invoke-DoomPB -Arguments @('--iwad', 'definitely-missing-doompb.wad', '--lump-info', 'PLAYPAL')
Test-Condition ($result.ExitCode -eq 1) "--lump-info with a missing WAD exits with 1 (got $($result.ExitCode))"

$result = Invoke-DoomPB -Arguments @('--dump-info', '--lump-info', 'PLAYPAL')
Test-Condition ($result.ExitCode -eq 2) "--dump-info and --lump-info conflict exits with 2 (got $($result.ExitCode))"

Write-Host ''
if ($script:failures -ne 0) {
    Write-Host "$($script:failures) of $($script:checks) checks failed." -ForegroundColor Red
    exit 1
}

Write-Host "All $($script:checks) checks passed." -ForegroundColor Green
exit 0
