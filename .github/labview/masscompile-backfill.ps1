<#
.SYNOPSIS
    Mass Compile reports across history using ONE warm Windows LabVIEW container.

.DESCRIPTION
    Bulk counterpart of masscompile.ps1. Walks every project-source-touching
    commit (oldest -> newest) and produces the same per-commit Mass Compile
    report (index.html + summary.json + masscompile.log) that the per-push
    workflow produces, so the dashboard's Mass Compile column can show a compile
    percentage for previous revisions too.

    A single container is started and kept warm; each commit is compiled via
    `docker exec` against a detached git worktree (no per-commit container churn
    or image re-pull). This is far faster than re-dispatching the per-push
    workflow once per commit (one image pull instead of N), and because the whole
    backfill is a SINGLE workflow run with a SINGLE gh-pages deploy at the end it
    sidesteps two problems with mass re-dispatch:
      * the shared `report-pages-deploy` concurrency group cancels all-but-one
        queued run (GitHub keeps only 1 running + 1 pending per group), and
      * concurrent peaceiris pushes to gh-pages race ("fetch first" rejections).

    Reports are staged deploy-ready under:
        <OutRoot>\<sha>\index.html | summary.json | masscompile.log
    which the workflow deploys to  masscompile/<sha>/...  with keep_files:true.

    Resumable + incremental: commits whose masscompile/<sha>/summary.json is
    already deployed are skipped (via -SkipListPath), and a -TimeBudgetMinutes
    cap lets a long backlog be processed across several runs.

.NOTES
    'Continue' (not 'Stop') is deliberate: git/docker/LabVIEWCLI write progress to
    stderr, which WinPS 5.1 would otherwise turn into terminating
    NativeCommandErrors. Success is judged by output presence, not stderr.
#>
param(
    [string]$WorkspaceRoot     = (Get-Location).Path,
    [string]$OutRoot           = '',
    [string]$Image             = 'nationalinstruments/labview:latest-windows',
    [int]   $MaxCommits        = 0,
    # File listing already-deployed report paths (one per line, e.g.
    # 'masscompile/<sha>/summary.json'). Used to skip commits already done.
    [string]$SkipListPath      = '',
    [int]   $TimeBudgetMinutes = 300
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

$WorkspaceRoot = (Resolve-Path $WorkspaceRoot).Path
if ($OutRoot -eq '') { $OutRoot = Join-Path $WorkspaceRoot 'ci-out\masscompile-backfill' }
$OpsHost = Join-Path $WorkspaceRoot '.github\labview'

$TempRoot = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [System.IO.Path]::GetTempPath() }
$WorkTreesHost = Join-Path $TempRoot 'lvci-mc-wt'
New-Item -ItemType Directory -Force -Path $OutRoot, $WorkTreesHost | Out-Null

$ContainerName = "lvci-mc-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"

# ── Project-source-touching commits, oldest first ────────────────────────────
# Same source extensions the dashboard uses to classify a "project" revision, so
# the backfill covers exactly the commits the dashboard shows by default.
$Commits = @(& git -C $WorkspaceRoot log --reverse --format='%H' -- `
    '*.vi' '*.vit' '*.ctl' '*.ctt' '*.lvclass' '*.lvlib' '*.lvproj')
if ($MaxCommits -gt 0 -and $Commits.Count -gt $MaxCommits) {
    $Commits = $Commits[($Commits.Count - $MaxCommits)..($Commits.Count - 1)]
}
Write-Host "Project-source commits to consider: $($Commits.Count)"

# Set of already-done SHAs (from the deployed report list) for incremental skip.
$Done = New-Object 'System.Collections.Generic.HashSet[string]'
if ($SkipListPath -ne '' -and (Test-Path $SkipListPath)) {
    foreach ($line in (Get-Content $SkipListPath)) {
        if ($line -match 'masscompile/([0-9a-f]+)/summary\.json') { [void]$Done.Add($Matches[1]) }
    }
    Write-Host "Already-done commits: $($Done.Count)"
}

# ── Start the long-lived container ───────────────────────────────────────────
& docker pull $Image | Out-Null
Write-Host "Starting warm container $ContainerName ..."
# NOTE: report OUTPUT is intentionally NOT a bind-mount. On Windows containers,
# files written inside the container to a host bind-mount are not reliably visible
# back on the host. We write to a container-internal dir (C:\cout) and `docker cp`
# each commit's report out to the host instead. The worktree (INPUT) is delivered
# via the C:\wt mount (host -> container direction is reliable).
& docker run -d --name $ContainerName `
    -v "${OpsHost}:C:\ops" `
    -v "${WorkTreesHost}:C:\wt" `
    $Image powershell -NoProfile -Command "while (`$true) { Start-Sleep -Seconds 3600 }" | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Failed to start container." }

# Live bind-mount probe (host files created after start must be visible inside).
$probe = Join-Path $WorkTreesHost '.probe'
Set-Content -Path $probe -Value 'ok' -Encoding ascii
$probeSeen = (& docker exec $ContainerName powershell -NoProfile -Command "if (Test-Path 'C:\wt\.probe') { 'yes' } else { 'no' }").Trim()
Remove-Item $probe -Force -ErrorAction SilentlyContinue
if ($probeSeen -ne 'yes') {
    & docker rm -f $ContainerName | Out-Null
    throw "Live bind-mount probe failed (container cannot see new host files under C:\wt)."
}

$deadline  = (Get-Date).AddMinutes($TimeBudgetMinutes)
$processed = 0
$skipped   = 0
$failed    = 0

try {
    foreach ($sha in $Commits) {
        $short = $sha.Substring(0, 7)

        # Resume: skip commits whose report is already deployed.
        if ($Done.Contains($sha)) { $skipped++; continue }

        if ((Get-Date) -gt $deadline) {
            Write-Host "Time budget reached - stopping before $short. Re-run to resume."
            break
        }

        # Detached worktree of this commit, mounted into the warm container at C:\wt.
        $hwt = Join-Path $WorkTreesHost "head-$sha"
        if (Test-Path $hwt) { & git -C $WorkspaceRoot worktree remove --force $hwt 2>$null | Out-Null }
        & git -C $WorkspaceRoot worktree add --detach $hwt $sha 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Warning "worktree failed for $short; skipping."; continue }

        try {
            # Compile into a CONTAINER-INTERNAL dir, then copy the result to the host.
            $cOut = "C:\cout\$sha"
            & docker exec $ContainerName powershell -NoProfile -Command "Remove-Item -Recurse -Force '$cOut' -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force -Path '$cOut' | Out-Null" | Out-Null
            & docker exec $ContainerName powershell -NoProfile -ExecutionPolicy Bypass `
                -File 'C:\ops\masscompile.ps1' `
                -WorkspaceRoot "C:\wt\head-$sha" `
                -ReportDir     "$cOut"
            $rc = $LASTEXITCODE
            Write-Host "[$short] masscompile exit=$rc"

            # Copy the rendered report out of the container to <OutRoot>\<sha>\.
            & docker cp "${ContainerName}:$cOut" "$OutRoot"
            if ($LASTEXITCODE -ne 0) { Write-Warning "docker cp failed for $short (continuing)." }
            & docker exec $ContainerName powershell -NoProfile -Command "Remove-Item -Recurse -Force '$cOut' -ErrorAction SilentlyContinue" | Out-Null

            # Only count it if the report actually landed on the host.
            if (Test-Path (Join-Path $OutRoot "$sha\summary.json")) {
                $processed++
            }
            else {
                Write-Warning "No summary.json produced for $short (report not generated)."
                $failed++
            }
        }
        finally {
            & git -C $WorkspaceRoot worktree remove --force $hwt 2>$null | Out-Null
        }
    }
}
finally {
    & docker rm -f $ContainerName 2>$null | Out-Null
    & git -C $WorkspaceRoot worktree prune 2>$null | Out-Null
}

Write-Host ""
Write-Host "=== Mass Compile backfill complete: $processed generated, $skipped skipped, $failed failed ==="
exit 0
