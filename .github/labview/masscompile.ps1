<#
.SYNOPSIS
    Runs LabVIEW Mass Compile on the workspace, then generates an HTML report.

.PARAMETER WorkspaceRoot
    Absolute path inside the container to the project root.
    Default: C:\workspace (GitHub Actions volume mount point)

.PARAMETER ReportDir
    Directory to write masscompile.log and index.html into.

.PARAMETER LabVIEWPath
    Path to LabVIEW.exe inside the container.
#>
param(
    [string]$WorkspaceRoot = 'C:\workspace',
    [string]$ReportDir     = 'C:\report',
    [string]$LabVIEWPath   = 'C:\Program Files\National Instruments\LabVIEW 2024\LabVIEW.exe'
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
$CliExe  = Resolve-LabVIEWCLI $LabVIEWPath
$LogFile = Join-Path $ReportDir 'masscompile.log'
$HtmlOut = Join-Path $ReportDir 'index.html'

New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null

Write-Host "=== Mass Compile ==="
Write-Host "  Workspace : $WorkspaceRoot"
Write-Host "  LabVIEW   : $LabVIEWPath"
Write-Host "  CLI       : $CliExe"
Write-Host ""

$Start = Get-Date

# Run MassCompile and tee output to log
& $CliExe `
    -OperationName MassCompile `
    -LabVIEWPath   $LabVIEWPath `
    -Target        $WorkspaceRoot `
    2>&1 | Tee-Object -FilePath $LogFile

$ExitCode = $LASTEXITCODE
$Duration = [math]::Round(((Get-Date) - $Start).TotalSeconds, 1)

# Parse log for error/warning counts (case-insensitive)
$LogText  = Get-Content $LogFile -Raw -ErrorAction SilentlyContinue
$Errors   = ([regex]::Matches($LogText, '(?i)\berror\b')).Count
$Warnings = ([regex]::Matches($LogText, '(?i)\bwarning\b')).Count

$Passed      = ($ExitCode -eq 0 -and $Errors -eq 0)
$StatusLabel = if ($Passed) { 'PASSED' } else { 'FAILED' }
$StatusColor = if ($Passed) { '#2ea043' } else { '#da3633' }

Write-Host ""
Write-Host "=== Result: $StatusLabel (exit=$ExitCode errors=$Errors warnings=$Warnings duration=${Duration}s) ==="

# ── Generate HTML report ─────────────────────────────────────────────────────
function Encode-Html([string]$s) {
    $s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;'
}

if ([string]::IsNullOrEmpty($LogText)) {
  $LogText = '(no output captured)'
}
$LogHtml  = Encode-Html $LogText
$ReportTs = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss UTC')

$Html = @"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Mass Compile — challenge-of-champions</title>
  <style>
    *{box-sizing:border-box}
    body{margin:0;padding:20px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#0d1117;color:#e6edf3}
    .card{background:#161b22;border:1px solid #30363d;border-radius:8px;padding:20px;margin-bottom:16px}
    h1{margin:0 0 12px;font-size:1.3em}
    .badge{display:inline-block;padding:3px 10px;border-radius:4px;font-weight:700;font-size:.85em;color:#fff;background:$StatusColor}
    .meta{margin-top:10px;font-size:.82em;color:#8b949e;display:flex;flex-wrap:wrap;gap:16px}
    pre{background:#0d1117;border:1px solid #30363d;border-radius:6px;padding:14px;font-size:.75em;white-space:pre-wrap;word-break:break-all;overflow-y:auto;max-height:65vh;margin:0}
  </style>
</head>
<body>
  <div class="card">
    <h1>Mass Compile — challenge-of-champions</h1>
    <span class="badge">$StatusLabel</span>
    <div class="meta">
      <span>Date: $ReportTs</span>
      <span>Duration: ${Duration}s</span>
      <span>Errors: $Errors</span>
      <span>Warnings: $Warnings</span>
    </div>
  </div>
  <pre>$LogHtml</pre>
</body>
</html>
"@

[System.IO.File]::WriteAllText($HtmlOut, $Html, [System.Text.UTF8Encoding]::new($false))
Write-Host "HTML report → $HtmlOut"

exit $ExitCode
