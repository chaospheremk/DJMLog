#Requires -Version 7.0

<#
.SYNOPSIS
    Installs a Git pre-push hook that runs Invoke-Build Build before each push.

.DESCRIPTION
    Creates or appends to the .git/hooks/pre-push file. If a pre-push hook
    already exists (e.g., from another tool), the Invoke-Build command is
    appended rather than overwriting the existing hook content.

.EXAMPLE
    .\scripts\Install-GitHooks.ps1

    Installs the pre-push hook in the current repository.
#>

[CmdletBinding()]
param()

$hooksDir = Join-Path $PSScriptRoot '../.git/hooks'
$hookPath = Join-Path $hooksDir 'pre-push'
$hookLine = "pwsh -NonInteractive -Command 'Invoke-Build Build'"

if (-not (Test-Path $hooksDir)) {
    Write-Error "Git hooks directory not found at '$hooksDir'. Are you in a git repository?"
    return
}

if (Test-Path $hookPath) {
    $existing = Get-Content $hookPath -Raw
    if ($existing -match 'Invoke-Build') {
        Write-Host 'pre-push hook already contains Invoke-Build — skipping.' -ForegroundColor Green
        return
    }
    Write-Warning 'Existing pre-push hook found — appending Invoke-Build command.'
    Add-Content $hookPath "`n$hookLine"
}
else {
    Set-Content $hookPath "#!/bin/sh`n$hookLine"
}

Write-Host 'pre-push hook installed. Invoke-Build Build will run before each push.' -ForegroundColor Green
