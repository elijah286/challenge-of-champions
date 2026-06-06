<#
.SYNOPSIS
    Generates VIDiff comparison reports for changed VIs (Windows container).

.DESCRIPTION
    For each VI that differs between base and head:
      - Modified  → CreateComparisonReport (side-by-side diff)
      - Added     → PrintToSingleFileHtml of the new VI (no base)
      - Deleted   → PrintToSingleFileHtml of the old VI (no head)

    Magic-byte check (LVIN / LVCC) skips non-LabVIEW files with .vi/.ctl extension.

.PARAMETER BaseDir
    Container path where the base commit checkout is mounted.

.PARAMETER HeadDir
    Container path where the head commit checkout is mounted.

.PARAMETER ChangedFiles
    Newline-separated list of changed files (relative workspace paths).

.PARAMETER ReportDir
    Output directory for HTML diff reports.

.PARAMETER LabVIEWPath
    Path to LabVIEW.exe inside the container.
#>
param(
    [string]$BaseDir      = 'C:\workspace-base',
    [string]$HeadDir      = 'C:\workspace',
    [string]$ChangedFiles = '',   # passed as env or piped
    [string]$ReportDir    = 'C:\report',
    [string]$LabVIEWPath  = 'C:\Program Files\National Instruments\LabVIEW 2024\LabVIEW.exe'
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
    if ($null -eq $cliCmd) { $cliCmd = Get-Command LabVIEWCLI -ErrorAction SilentlyContinue }
    if ($null -ne $cliCmd -and $cliCmd.Source) { return $cliCmd.Source }
    $candidate = Join-Path (Split-Path $LabVIEWExePath) 'LabVIEWCLI.exe'
    if (Test-Path $candidate) { return $candidate }
    throw "LabVIEWCLI not found on PATH and not found beside LabVIEW.exe ('$candidate')."
}

$LabVIEWPath = Resolve-LabVIEWPath $LabVIEWPath
$CliExe      = Resolve-LabVIEWCLI $LabVIEWPath
# AdditionalOperationDirectory is searched recursively for the operation class,
# so point it at .github\labview (the parent of the PrintToSingleFileHtml folder).
$PrintToHtmlOp   = Join-Path $HeadDir '.github\labview'

New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null

# ── Helper: is this a real LabVIEW binary? ───────────────────────────────────
function Test-IsLabVIEWFile([string]$Path) {
    if (-not (Test-Path $Path)) { return $false }
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        if ($bytes.Length -lt 4) { return $false }
        # LabVIEW files use the Mac resource fork format starting with RSRC
        $magic = [System.Text.Encoding]::ASCII.GetString($bytes[0..3])
        return ($magic -eq 'RSRC')
    } catch { return $false }
}

# ── Parse changed-file list ──────────────────────────────────────────────────
if ($ChangedFiles -eq '') {
    $ChangedFiles = $Env:CHANGED_FILES
}
$Files = $ChangedFiles -split "`n" | Where-Object { $_ -match '\.(vi|ctl)$' }

if ($Files.Count -eq 0) {
    Write-Host 'No .vi/.ctl files changed — nothing to diff.'
    exit 0
}

$Results   = [System.Collections.Generic.List[hashtable]]::new()
$Processed = 0
$Errors    = 0

# LabVIEWCLI prints operation output to stderr; relax ErrorActionPreference so that
# informational stderr is not treated as a terminating error. Each operation's
# success is judged by $LASTEXITCODE inside the loop.
$ErrorActionPreference = 'Continue'

foreach ($RelPath in $Files) {
    $RelPath  = $RelPath.Trim().TrimStart('/')
    $BasePath = Join-Path $BaseDir $RelPath
    $HeadPath = Join-Path $HeadDir $RelPath
    $SafeName = ($RelPath -replace '[/\\]','-') -replace '[^a-zA-Z0-9._-]','_'
    $OutDir   = Join-Path $ReportDir $SafeName
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

    $BaseExists = Test-Path $BasePath
    $HeadExists = Test-Path $HeadPath
    $BaseIsVI   = Test-IsLabVIEWFile $BasePath
    $HeadIsVI   = Test-IsLabVIEWFile $HeadPath

    Write-Host "── $RelPath (base=$BaseExists/$BaseIsVI head=$HeadExists/$HeadIsVI)"

    try {
        if ($BaseExists -and $BaseIsVI -and $HeadExists -and $HeadIsVI) {
            # Modified — single-step HTML comparison report.
            # -Headless is REQUIRED for LabVIEW 2026+ inside Windows containers.
            $HtmlOut = Join-Path $OutDir 'index.html'
            & $CliExe `
                -LogToConsole  TRUE `
                -OperationName CreateComparisonReport `
                -VI1           $BasePath `
                -VI2           $HeadPath `
                -ReportType    html `
                -ReportPath    $HtmlOut `
                -LabVIEWPath   $LabVIEWPath `
                -Headless
            if ($LASTEXITCODE -ne 0) { throw "CreateComparisonReport failed (exit $LASTEXITCODE)" }
            $Results.Add(@{File=$RelPath; Type='modified'; Html="$SafeName/index.html"})

        } elseif ($HeadExists -and $HeadIsVI) {
            # Added — snapshot of new file only
            $HtmlOut = Join-Path $OutDir 'index.html'
            & $CliExe `
                -OperationName                PrintToSingleFileHtml `
                -LabVIEWPath                  $LabVIEWPath `
                -AdditionalOperationDirectory $PrintToHtmlOp `
                -LogToConsole                 TRUE `
                -VI                           $HeadPath `
                -OutputPath                   $HtmlOut `
                -o -c `
                -Headless
            if ($LASTEXITCODE -ne 0) { throw "PrintToSingleFileHtml (added) failed (exit $LASTEXITCODE)" }
            $Results.Add(@{File=$RelPath; Type='added'; Html="$SafeName/index.html"})

        } elseif ($BaseExists -and $BaseIsVI) {
            # Deleted — snapshot of old file
            $HtmlOut = Join-Path $OutDir 'index.html'
            & $CliExe `
                -OperationName                PrintToSingleFileHtml `
                -LabVIEWPath                  $LabVIEWPath `
                -AdditionalOperationDirectory $PrintToHtmlOp `
                -LogToConsole                 TRUE `
                -VI                           $BasePath `
                -OutputPath                   $HtmlOut `
                -o -c `
                -Headless
            if ($LASTEXITCODE -ne 0) { throw "PrintToSingleFileHtml (deleted) failed (exit $LASTEXITCODE)" }
            $Results.Add(@{File=$RelPath; Type='deleted'; Html="$SafeName/index.html"})

        } else {
            Write-Host "  Skipping '$RelPath' — not a valid LabVIEW binary"
            continue
        }
        $Processed++
    } catch {
        Write-Warning "  ERROR processing ${RelPath}: $_"
        $Errors++
    }
}

Write-Host ""
Write-Host "=== VIDiff complete: $Processed processed, $Errors errors ==="

# ── Generate index page ──────────────────────────────────────────────────────
$Rows = ($Results | ForEach-Object {
    $badge  = switch ($_.Type) {
        'modified' { '<span style="background:#9a6700;color:#fff;padding:2px 8px;border-radius:4px;font-size:.8em">modified</span>' }
        'added'    { '<span style="background:#2ea043;color:#fff;padding:2px 8px;border-radius:4px;font-size:.8em">added</span>' }
        'deleted'  { '<span style="background:#da3633;color:#fff;padding:2px 8px;border-radius:4px;font-size:.8em">deleted</span>' }
    }
    "<tr><td style='padding:8px'>$badge</td><td style='padding:8px;font-family:monospace'>$($_.File)</td><td style='padding:8px'><a href='$($_.Html)' style='color:#58a6ff'>View report</a></td></tr>"
}) -join "`n"

$IndexHtml = @"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>VIDiff — challenge-of-champions</title>
  <style>
    body{margin:0;padding:20px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#0d1117;color:#e6edf3}
    h1{font-size:1.3em}table{border-collapse:collapse;width:100%;background:#161b22;border:1px solid #30363d;border-radius:8px}
    th{text-align:left;padding:10px 8px;border-bottom:1px solid #30363d;color:#8b949e;font-size:.85em}
    tr:hover{background:#1c2128}a{color:#58a6ff}
  </style>
</head>
<body>
  <h1>VIDiff — challenge-of-champions</h1>
  <p style="color:#8b949e;font-size:.9em">$Processed file(s) compared | $Errors error(s)</p>
  <table>
    <thead><tr><th>Status</th><th>File</th><th>Report</th></tr></thead>
    <tbody>$Rows</tbody>
  </table>
</body>
</html>
"@

[System.IO.File]::WriteAllText((Join-Path $ReportDir 'index.html'), $IndexHtml, [System.Text.UTF8Encoding]::new($false))
Write-Host "Index → $(Join-Path $ReportDir 'index.html')"

if ($Errors -gt 0) { exit 1 }
exit 0
