<#
.SYNOPSIS
Structured JSONL logging module for PowerShell 7+.

.DESCRIPTION
Module loader. Initialises shared state then dot-sources all private helpers
and public functions from their respective subdirectories.

Exports six functions:
  Set-DJMLogConfig, Write-DJMLog, Read-DJMLog, Send-DJMLogBuffer,
  ConvertTo-DJMDictionary, ConvertTo-DJMOrderedPSObject

.NOTES
Requires PowerShell 7 or later.
#>

# Module-level state — shared across all dot-sourced functions via $script: scope
$script:DefaultLogPath           = $null
$script:DefaultMaxSizeMB         = 0
$script:DefaultMutexTimeoutMs    = 2000
$script:DefaultMinLevel          = 'DEBUG'   # lowest threshold — everything is written
$script:DefaultRotationSchedule  = 'None'    # time-based rotation disabled
$script:DefaultRetainDays        = 0         # 0 = keep all rotated files indefinitely
$script:DefaultRetainFiles       = 0         # 0 = keep all rotated files indefinitely
$script:DefaultIncludeCaller     = $true     # capture caller script/line automatically

# Azure Log Analytics integration
$script:LogAnalyticsEnabled     = $false
$script:CloudEnvironment        = 'GCCHigh'   # Commercial | GCCHigh | DoD
$script:DcrEndpointUri          = $null
$script:DcrImmutableId          = $null
$script:DcrStreamName           = $null
$script:TenantId                = $null
$script:AppId                   = $null
$script:AppSecret               = $null
$script:CertificateSubject      = $null        # e.g. 'CN=DJMLog-Auth'
$script:CertificateThumbprint   = $null        # pin to specific cert
$script:FlushThreshold          = 100
$script:MaxBufferSize           = 5000
$script:MaxFlushRetries         = 3
$script:LogBuffer               = [System.Collections.Generic.List[hashtable]]::new()
$script:BearerToken             = $null
$script:BearerTokenExternal     = $null        # user-supplied token via -BearerToken
$script:TokenExpiry             = [datetime]::MinValue
$script:FlushFailureCount       = 0
$script:AutoFlushDisabled       = $false

# Named mutex shared across all runspaces on this machine via the OS kernel.
# Serialises AppendAllText calls so parallel writers never contend on the file.
$script:LogMutex = [System.Threading.Mutex]::new($false, 'DJMLog_WriteAccess')

# Dispose mutex when module is removed to avoid OS resource leaks
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    if ($script:LogMutex) { $script:LogMutex.Dispose() }
}

# Dot-source all private helpers then all public functions
foreach ($file in (Get-ChildItem -Path "$PSScriptRoot\Private" -Filter '*.ps1')) { . $file.FullName }
foreach ($file in (Get-ChildItem -Path "$PSScriptRoot\Public"  -Filter '*.ps1')) { . $file.FullName }
