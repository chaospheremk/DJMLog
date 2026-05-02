#Requires -Version 7.0

<#
.SYNOPSIS
    Run a scriptblock and force [System.Environment]::Exit on completion.

.DESCRIPTION
    Wraps a scriptblock so a non-interactive pwsh subprocess always terminates
    after the script returns, regardless of any background pipeline threads
    owned by an imported DJMLog module. PowerShell's `exit` keyword routes
    through flow-control machinery that respects foreground threads;
    [System.Environment]::Exit forces the .NET host down.

    This is required at every non-interactive entry point that imports DJMLog
    (directly or via Invoke-Build / Pester). The v2.0 async writer's runspace
    plus Task.Run worker keeps pwsh.exe alive after the script finishes
    (see ADR-019 / ADR-026 / ADR-030 / BUG-023). Interactive hosts are not
    affected because Remove-Module returns control to the user without waiting
    on writer-thread shutdown.

    A "real" hard-stop disposal path was attempted earlier (PowerShell.Stop +
    EndInvoke + Dispose) and observed to leak a foreground pipeline thread on
    Remove-Module + Import-Module cycles. There is no public API to mark a
    PowerShell pipeline thread background before Invoke is called, so this
    [Environment]::Exit wrapper is the standing workaround. ADR-030 records
    why we are deferring the hard-stop attempt indefinitely.

.PARAMETER Script
    The scriptblock to run.

.EXAMPLE
    & ./scripts/Invoke-WithDJMHostExit.ps1 -Script { Invoke-Build Test -Configuration Release }

    Runs the test pipeline and forces a clean process exit afterwards. This is
    the `-Command`-mode invocation form used by the GitHub Actions workflows
    (`shell: pwsh` runs each step under `pwsh -Command`).

.EXAMPLE
    pwsh -NoProfile -Command "& './scripts/Invoke-WithDJMHostExit.ps1' -Script { Invoke-Build TestStress }"

    The form used by `scripts/Invoke-StressDrill.ps1` to spawn each iteration.
    `pwsh -File` cannot bind scriptblock literals as parameter values, so the
    drill harness uses `-Command` instead.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [object]$Script
)

# Accept either a [scriptblock] (call-site invocation) or a [string]
# (so the helper can also be driven via `pwsh -File`, which marshals all
# arguments as strings). String input is parsed once with ScriptBlock::Create.
$block = if ($Script -is [scriptblock]) {
    $Script
}
else {
    [scriptblock]::Create([string]$Script)
}

try {
    & $block
    [System.Environment]::Exit(($LASTEXITCODE ?? 0))
}
catch {
    Write-Host $_
    [System.Environment]::Exit(1)
}
