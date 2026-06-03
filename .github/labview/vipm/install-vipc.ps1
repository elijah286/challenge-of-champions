<#
.SYNOPSIS
    Installs VIPM and applies all .vipc dependency files found in C:\vipm.
    This script runs INSIDE the Docker build container (Windows Server Core).

.NOTES
    Adjust $VipmInstallerUrl to the latest VIPM release URL from https://vipm.jki.net
    Adjust $LabVIEWVersion  to match the LabVIEW version in the base NI image.
#>

$ErrorActionPreference = 'Stop'
$ProgressPreference   = 'SilentlyContinue'

$VipmDir          = 'C:\Program Files\JKI\VI Package Manager'
$VipmExe          = "$VipmDir\vipm.exe"
$VipcDir          = 'C:\vipm'
$LabVIEWVersion   = '2024'   # match the LabVIEW version in the NI base image
$VipmInstallerUrl = 'https://vipm.jki.net/l/download/vipm_2024_x64.exe'

# ── 1. Install VIPM if not already present ───────────────────────────────────
if (-not (Test-Path $VipmExe)) {
    Write-Host 'VIPM not found — downloading installer...'
    $InstallerFile = Join-Path $Env:TEMP 'vipm-installer.exe'
    Invoke-WebRequest -Uri $VipmInstallerUrl -OutFile $InstallerFile -UseBasicParsing

    Write-Host 'Running VIPM installer silently...'
    $p = Start-Process -FilePath $InstallerFile `
        -ArgumentList '/SILENT', '/NORESTART' `
        -Wait -PassThru
    if ($p.ExitCode -ne 0) {
        Write-Error "VIPM installer exited with code $($p.ExitCode)"
        exit 1
    }
    Write-Host "VIPM installed to: $VipmDir"
}

# ── 2. Apply each .vipc file ─────────────────────────────────────────────────
$vipcFiles = @(Get-ChildItem $VipcDir -Filter '*.vipc')
if ($vipcFiles.Count -eq 0) {
    Write-Host 'No .vipc files found — nothing to apply.'
    exit 0
}

foreach ($vipc in $vipcFiles) {
    Write-Host "Applying VIPC: $($vipc.Name)"
    & $VipmExe apply_vipc `
        -vipc_file          $vipc.FullName `
        -labview_version    $LabVIEWVersion `
        -accept_agreements  true
    if ($LASTEXITCODE -ne 0) {
        Write-Error "VIPM failed to apply '$($vipc.Name)' — exit code $LASTEXITCODE"
        exit 1
    }
}

Write-Host 'All VIPC files applied successfully.'
