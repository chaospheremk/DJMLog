<#
.SYNOPSIS
Structured JSONL logging module for PowerShell 7+.

.DESCRIPTION
Module loader. Initialises shared state then dot-sources all private helpers
and public functions from their respective subdirectories.

Exports five functions:
  Set-DJMLogConfig, Write-DJMLog, Read-DJMLog,
  ConvertTo-DJMDictionary, ConvertTo-DJMOrderedPSObject

.NOTES
Requires PowerShell 7 or later.
#>

# Module-level state — shared across all dot-sourced functions via $script: scope
$script:DefaultLogPath        = $null
$script:DefaultMaxSizeMB      = 0
$script:DefaultMutexTimeoutMs = 2000

# Named mutex shared across all runspaces on this machine via the OS kernel.
# Serialises AppendAllText calls so parallel writers never contend on the file.
$script:LogMutex = [System.Threading.Mutex]::new($false, 'DJMLog_WriteAccess')

# Dot-source all private helpers then all public functions
foreach ($file in (Get-ChildItem -Path "$PSScriptRoot\Private" -Filter '*.ps1')) { . $file.FullName }
foreach ($file in (Get-ChildItem -Path "$PSScriptRoot\Public"  -Filter '*.ps1')) { . $file.FullName }
