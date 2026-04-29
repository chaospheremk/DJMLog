<#
.SYNOPSIS
    Runs the AsyncWriter stress test (Invoke-Build TestStress) N times back-to-back
    and captures wall-clock + leaked-process counts per iteration.

.DESCRIPTION
    Phase 3's exit criteria call for the AsyncWriter stress test to pass 20× back-to-back.
    Each iteration spawns a fresh `pwsh -NoProfile -Command "Invoke-Build TestStress"`
    subprocess so module/runspace state cannot accumulate across runs.

    The inner pwsh command is wrapped in `[System.Environment]::Exit($LASTEXITCODE)`
    because the v2.0 async writer's runspace + Task.Run worker can keep the host
    process alive after Invoke-Pester returns. Without the explicit Exit, the
    subprocess hangs (~19 minutes in CI, indefinitely locally) and the next
    iteration blocks on the `& pwsh ...` boundary — surfacing as the "47s -> 5+ min"
    pattern observed during the v2.0 release window. The same wrapper is already
    used by `.github/workflows/release.yml` (added in PR #48); this script
    applies it for local stress drilling.

.PARAMETER Iterations
    Number of consecutive runs (default 20).

.PARAMETER OutDir
    Output directory for per-iteration logs and the summary CSV. Defaults to a
    timestamped subfolder under stress-runs/ which is git-ignored.
#>
[CmdletBinding()]
param(
    [int]$Iterations = 20,
    [string]$OutDir  = (Join-Path (Join-Path $PSScriptRoot '..\stress-runs') ('drill-' + (Get-Date -Format 'yyyyMMdd-HHmmss')))
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$OutDir = (Resolve-Path $OutDir).Path
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$summary = [System.Collections.Generic.List[pscustomobject]]::new()

for ($i = 1; $i -le $Iterations; $i++) {
    $logFile = Join-Path $OutDir ("run-{0:D2}.log" -f $i)
    Write-Host "[drill] iteration $i/$Iterations -> $logFile" -ForegroundColor Cyan

    $beforeIds = (Get-Process pwsh -ErrorAction SilentlyContinue).Id

    $cmd = "Set-Location '$repoRoot'; try { Invoke-Build TestStress; [System.Environment]::Exit(`$LASTEXITCODE) } catch { Write-Host `$_; [System.Environment]::Exit(1) }"
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    & pwsh -NoProfile -Command $cmd *> $logFile
    $exit = $LASTEXITCODE
    $sw.Stop()

    $afterIds = (Get-Process pwsh -ErrorAction SilentlyContinue).Id
    $leaked   = @($afterIds | Where-Object { $beforeIds -notcontains $_ })

    $passed = (Select-String -Path $logFile -Pattern 'Tests Passed: 1' -Quiet) -eq $true
    $failed = (Select-String -Path $logFile -Pattern 'Failed: 0,'      -Quiet) -ne $true

    $row = [pscustomobject]@{
        Iter     = $i
        ExitCode = $exit
        Passed   = $passed
        Failed   = $failed
        WallSec  = [math]::Round($sw.Elapsed.TotalSeconds, 1)
        Leaked   = $leaked.Count
        LeakIds  = ($leaked -join ',')
    }
    $summary.Add($row)
    Write-Host ("  exit={0} pass={1} wall={2}s leaked={3}" -f $exit, $passed, $row.WallSec, $leaked.Count) -ForegroundColor Yellow
}

$summary | Format-Table -AutoSize | Out-String | Write-Host
$summaryPath = Join-Path $OutDir 'drill-summary.csv'
$summary | Export-Csv -Path $summaryPath -NoTypeInformation -Encoding UTF8
Write-Host "[drill] summary saved to $summaryPath"
