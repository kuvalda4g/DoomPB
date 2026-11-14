<#
.SYNOPSIS
    Runs the DoomPB M0 verification suite on Windows.

.DESCRIPTION
    Performs a real PureBasic syntax check, a real build, the synthetic WAD
    header/directory unit tests, and smoke tests against the produced
    executable: --version, --help, no-argument startup and unknown-option
    handling. No commercial game data and no display are needed.

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
    param([switch]$Check, [switch]$Test)
    if ([string]::IsNullOrWhiteSpace($CompilerPath)) {
        & $buildScript -Check:$Check -Test:$Test
    } else {
        & $buildScript -Check:$Check -Test:$Test -CompilerPath $CompilerPath
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
Write-Host '== WAD header/directory unit tests =='
& $unitTestExe
$status = $LASTEXITCODE
Test-Condition ($status -eq 0) "synthetic WAD tests exit with 0 (got $status)"

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

Write-Host ''
if ($script:failures -ne 0) {
    Write-Host "$($script:failures) of $($script:checks) checks failed." -ForegroundColor Red
    exit 1
}

Write-Host "All $($script:checks) checks passed." -ForegroundColor Green
exit 0
