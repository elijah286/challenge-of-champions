# syntax=docker/dockerfile:1
# =============================================================================
# LabVIEW CI image for challenge-of-champions
# =============================================================================
# Extends the official NI LabVIEW Windows container with:
#   - VI Analyzer support package (ni-viawin-labview-support) via nipkg
#   - VIPM + COTC Dependencies.vipc baked in at build time
#
# Build args:
#   NIPM_FEED_URL   – NI nipkg feed for the target LabVIEW version
#   VIA_SUPPORT_PACKAGE – nipkg package name for VI Analyzer support
# =============================================================================

ARG NIPM_FEED_URL=https://download.ni.com/support/nipkg/products/ni-l/ni-labview-2024/24.1/released
ARG VIA_SUPPORT_PACKAGE=ni-viawin-labview-support

FROM nationalinstruments/labview:latest-windows

ARG NIPM_FEED_URL
ARG VIA_SUPPORT_PACKAGE

SHELL ["powershell", "-Command", \
    "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

# ---------------------------------------------------------------------------- #
# Install VI Analyzer support via nipkg
# nipkg.exe ships with LabVIEW / NI Package Manager at the path below
# ---------------------------------------------------------------------------- #
RUN $nipkg = 'C:\Program Files\National Instruments\NI Package Manager\nipkg.exe'; \
    Write-Host "Adding nipkg feed: $Env:NIPM_FEED_URL"; \
    & $nipkg feed-add --name=ni-labview-2024 $Env:NIPM_FEED_URL; \
    Write-Host "Installing $Env:VIA_SUPPORT_PACKAGE ..."; \
    & $nipkg install --accept-eulas $Env:VIA_SUPPORT_PACKAGE; \
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; \
    Write-Host 'VI Analyzer support installed.'

# ---------------------------------------------------------------------------- #
# Stage VIPM hook folder (.vipc files + install-vipc.ps1)
# The build context is the repo root so both COPY paths are reachable
# ---------------------------------------------------------------------------- #
COPY .github/labview/vipm/ C:/vipm/

# Copy the project-level VIPC file from the repo root into the staging folder
# (challenge-of-champions ships its VIPM deps as "COTC Dependencies.vipc")
COPY ["COTC Dependencies.vipc", "C:/vipm/"]

# ---------------------------------------------------------------------------- #
# Conditionally install VIPM / apply VIPC files
#   - No .vipc files  → skip silently
#   - .vipc present but install-vipc.ps1 missing → fail loudly
# ---------------------------------------------------------------------------- #
RUN $vipcFiles = @(Get-ChildItem 'C:\vipm' -Filter '*.vipc' -ErrorAction SilentlyContinue); \
    if ($vipcFiles.Count -gt 0) { \
        $installScript = 'C:\vipm\install-vipc.ps1'; \
        if (-not (Test-Path $installScript)) { \
            Write-Error 'ERROR: .vipc files found in C:\vipm but install-vipc.ps1 is missing. Create .github/labview/vipm/install-vipc.ps1.'; \
            exit 1 \
        }; \
        Write-Host ("Applying {0} VIPC files via install-vipc.ps1 ..." -f $vipcFiles.Count); \
        & $installScript; \
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE } \
    } else { \
        Write-Host 'No .vipc files found - skipping VIPM installation.' \
    }
