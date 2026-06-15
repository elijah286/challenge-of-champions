<#
.SYNOPSIS
    Runs LabVIEW VI Analyzer (Windows container) with the full default test set
    and writes the native VI Analyzer HTML report.

.DESCRIPTION
    Passing the workspace *directory* as -ConfigPath makes LabVIEWCLI run the full
    default VI Analyzer test configuration against every VI under it. This requires
    the VI Analyzer test LLBs, which ship in the ni-viawin-labview-support package
    baked into the custom CI image (.github/docker/labview-ci.Dockerfile). On the
    bare NI base image no tests are installed and the report shows "0 tests run".

.PARAMETER WorkspaceRoot
    Absolute path to the project inside the container. Default: C:\workspace

.PARAMETER ReportDir
    Output directory for the HTML report (written as index.html).

.PARAMETER LabVIEWPath
    Path to LabVIEW.exe inside the container.
#>
param(
    [string]$WorkspaceRoot = 'C:\workspace',
    [string]$ReportDir     = 'C:\report',
    [string]$LabVIEWPath   = 'C:\Program Files\National Instruments\LabVIEW 2026\LabVIEW.exe'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

function Resolve-LabVIEWPath([string]$PreferredPath) {
    if ($PreferredPath -and (Test-Path $PreferredPath)) {
        return $PreferredPath
    }

    $candidates = @(Get-ChildItem 'C:\Program Files\National Instruments' -Directory -Filter 'LabVIEW *' -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName 'LabVIEW.exe' } |
        Where-Object { Test-Path $_ })

    if ($candidates.Count -gt 0) {
        return $candidates[0]
    }

    throw "LabVIEW.exe not found. Checked preferred path '$PreferredPath' and C:\Program Files\National Instruments\LabVIEW *"
}

function Resolve-LabVIEWCLI([string]$LabVIEWExePath) {
    $cliCmd = Get-Command LabVIEWCLI.exe -ErrorAction SilentlyContinue
    if ($null -eq $cliCmd) {
        $cliCmd = Get-Command LabVIEWCLI -ErrorAction SilentlyContinue
    }
    if ($null -ne $cliCmd -and $cliCmd.Source) {
        return $cliCmd.Source
    }

    $candidate = Join-Path (Split-Path $LabVIEWExePath) 'LabVIEWCLI.exe'
    if (Test-Path $candidate) {
        return $candidate
    }

    throw "LabVIEWCLI not found on PATH and not found beside LabVIEW.exe ('$candidate')."
}

$LabVIEWPath = Resolve-LabVIEWPath $LabVIEWPath
$CliExe      = Resolve-LabVIEWCLI $LabVIEWPath
$HtmlOut     = Join-Path $ReportDir 'index.html'

New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null

Write-Host "=== VI Analyzer (Windows) ==="
Write-Host "  Workspace      : $WorkspaceRoot"
Write-Host "  LabVIEW        : $LabVIEWPath"
Write-Host "  CLI            : $CliExe"
Write-Host "  Report (HTML)  : $HtmlOut"
Write-Host ""

$Start = Get-Date

# Passing the workspace DIRECTORY as -ConfigPath runs the full default VI Analyzer
# test set against every VI under it (requires the VI Analyzer test LLBs from
# ni-viawin-labview-support, baked into the custom CI image). -ReportSaveType HTML
# emits the native, richly formatted VI Analyzer report.
# NOTE: -Headless is REQUIRED for LabVIEW 2026+ inside Windows containers, otherwise
# LabVIEWCLI cannot establish a VI Server connection (error -350000).
& $CliExe `
    -LogToConsole   TRUE `
    -OperationName  RunVIAnalyzer `
    -ConfigPath     $WorkspaceRoot `
    -ReportPath     $HtmlOut `
    -ReportSaveType HTML `
    -LabVIEWPath    $LabVIEWPath `
    -Headless

$ExitCode = $LASTEXITCODE
$Duration = [math]::Round(((Get-Date) - $Start).TotalSeconds, 1)

Write-Host ""
Write-Host "=== VI Analyzer finished (exit=$ExitCode duration=${Duration}s) ==="

if (Test-Path $HtmlOut) {
    $size = (Get-Item $HtmlOut).Length
    Write-Host "HTML report -> $HtmlOut ($size bytes)"
} else {
    Write-Warning "No HTML report was generated at $HtmlOut"
}

# Exit code 3 = analysis succeeded but found rule failures -> treat as success
# (failures are detailed in the report). Any other non-zero code is a real error.
if ($ExitCode -eq 3) {
    Write-Host "VI Analyzer completed with rule failures (exit 3) - see report."
    exit 0
} elseif ($ExitCode -ne 0) {
    exit $ExitCode
}

exit 0
