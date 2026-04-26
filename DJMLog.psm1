<#
.SYNOPSIS
Structured JSONL logging module for PowerShell 7+.

.DESCRIPTION
Module loader. Initialises shared state then dot-sources all private helpers
and public functions from their respective subdirectories.

Exports seven functions:
  Set-DJMLogConfig, Write-DJMLog, Read-DJMLog, Send-DJMLogBuffer,
  Get-DJMLogDiagnostics, ConvertTo-DJMDictionary, ConvertTo-DJMOrderedPSObject

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
$script:MaxBufferBytes          = 52428800     # 50 MB byte-level cap on the buffer
$script:MaxFlushRetries         = 3
$script:LogBuffer               = [System.Collections.Generic.List[hashtable]]::new()
$script:BufferByteTotal         = 0            # running serialised byte total tracked alongside the buffer
$script:BearerToken             = $null
$script:BearerTokenExternal     = $null        # user-supplied token via -BearerToken
$script:TokenExpiry             = [datetime]::MinValue
$script:FlushFailureCount       = 0
$script:AutoFlushDisabled       = $false
$script:AutoFlushOpenedAtUtc    = $null        # set when circuit breaker trips; cleared on close
$script:HalfOpenAfterSeconds    = 300          # half-open probe window per ADR-017

# Internal error queue (SelfLog) — last 100 errors, FIFO. Surfaced via Get-DJMLogDiagnostics.
$script:InternalErrors          = [System.Collections.Generic.Queue[pscustomobject]]::new()
$script:InternalErrorsMaxSize   = 100

# In-process semaphore guarding $script:LogBuffer reads/writes. Same-process only —
# the named OS mutex serialises file appends across runspaces; this semaphore is the
# v1.1 interim fix for the buffer race (superseded by the async writer in v2.0).
$script:BufferLock = [System.Threading.SemaphoreSlim]::new(1, 1)

# Named mutex shared across all runspaces on this machine via the OS kernel.
# Serialises AppendAllText calls so parallel writers never contend on the file.
$script:LogMutex = [System.Threading.Mutex]::new($false, 'DJMLog_WriteAccess')

# Dispose mutex + semaphore when module is removed to avoid OS resource leaks
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    if ($script:LogMutex)   { $script:LogMutex.Dispose() }
    if ($script:BufferLock) { $script:BufferLock.Dispose() }
}

# Dot-source all private helpers then all public functions. Wrap each in
# try/catch so a single bad file leaves the module usable for the rest. Failures
# are queued in the SelfLog and re-thrown only if any FunctionsToExport entry
# can't be resolved after loading — we won't ship a half-loaded module.
$loadFailures = [System.Collections.Generic.List[string]]::new()
foreach ($file in @(
        Get-ChildItem -Path "$PSScriptRoot\Private" -Filter '*.ps1'
        Get-ChildItem -Path "$PSScriptRoot\Public"  -Filter '*.ps1'
    )) {
    try {
        . $file.FullName
    }
    catch {
        $loadFailures.Add("$($file.Name): $($_.Exception.Message)")
        try {
            $script:InternalErrors.Enqueue([pscustomobject]@{
                UtcTimestamp = [datetime]::UtcNow.ToString('o')
                Source       = 'Module Load'
                Message      = "Failed to load $($file.Name): $($_.Exception.Message)"
                Exception    = $_.Exception
            })
        }
        catch {
            # SelfLog itself failed — write to stderr so something surfaces
            [Console]::Error.WriteLine("DJMLog: failed to load $($file.Name) and could not enqueue SelfLog: $($_.Exception.Message)")
        }
    }
}

if ($loadFailures.Count -gt 0) {
    $manifestPath = Join-Path $PSScriptRoot 'DJMLog.psd1'
    if (Test-Path -LiteralPath $manifestPath) {
        $manifest  = Import-PowerShellDataFile -LiteralPath $manifestPath
        $exports   = @($manifest.FunctionsToExport)
        $missing   = @($exports.Where({ -not (Get-Command -Name $_ -ErrorAction SilentlyContinue) }))
        if ($missing.Count -gt 0) {
            throw "DJMLog failed to load: missing exported functions [$($missing -join ', ')]. Failures: $($loadFailures -join '; ')"
        }
    }
    Write-Warning "DJMLog: $($loadFailures.Count) source file(s) failed to load but all exports resolved. See Get-DJMLogDiagnostics for details."
}
