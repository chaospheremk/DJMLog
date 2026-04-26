<#
.SYNOPSIS
Structured JSONL logging module for PowerShell 7+ (v2.0 — async writer + sinks).

.DESCRIPTION
Module loader. Initialises shared state, dot-sources private helpers and public
functions, then spawns the async writer runspace (per ADR-019).

Exports eleven functions:
  Set-DJMLogConfig, Write-DJMLog, Read-DJMLog, Send-DJMLogBuffer,
  Flush-DJMLog, Wait-DJMLog, Start-DJMActivity, Stop-DJMActivity,
  Get-DJMLogDiagnostics, ConvertTo-DJMDictionary, ConvertTo-DJMOrderedPSObject

.NOTES
Requires PowerShell 7 or later.
#>

# Module-level state — shared across all dot-sourced functions via $script: scope
$script:ModuleManifestPath       = (Join-Path $PSScriptRoot 'DJMLog.psd1')

# File-sink defaults
$script:DefaultLogPath           = $null
$script:DefaultMaxSizeMB         = 0
$script:DefaultMutexTimeoutMs    = 2000
$script:DefaultMinLevel          = 'DEBUG'   # lowest threshold — everything is written
$script:DefaultRotationSchedule  = 'None'    # time-based rotation disabled
$script:DefaultRetainDays        = 0         # 0 = keep all rotated files indefinitely
$script:DefaultRetainFiles       = 0         # 0 = keep all rotated files indefinitely
$script:DefaultIncludeCaller     = $true     # capture caller script/line automatically
$script:DefaultIncludeHostContext = $true    # schema v2: host enrichment

# Sinks (multi-target output)
$script:Sinks                    = @('File')

# Async writer (v2.0 — ADR-019)
$script:ChannelCapacity          = 10000     # bounded channel; DropOldest when full
$script:WriterChannel            = $null
$script:WriterShared             = $null
$script:WriterRunspace           = $null
$script:WriterPS                 = $null
$script:WriterAsyncResult        = $null

# Activity stack (v2.0 — ADR-021)
$script:ActivityStack            = $null     # lazily allocated per runspace

# Redaction (v2.0 — ADR-023)
$script:RedactionPatterns        = @()       # configurable regex array
$script:RedactionPresets         = @()       # 'Email' | 'BearerToken' | 'CreditCard'

# Sampling (v2.0 — ADR-024)
$script:SampleRate               = $null     # hashtable per-level (e.g. @{ DEBUG = 0.01 })

# Schema (v2.0 — ADR-022)
$script:SchemaVersion            = '2'

# Azure Log Analytics integration (mostly mirrors v1.x — buffer relocated to writer)
$script:LogAnalyticsEnabled      = $false
$script:CloudEnvironment         = 'GCCHigh'  # Commercial | GCCHigh | DoD
$script:DcrEndpointUri           = $null
$script:DcrImmutableId           = $null
$script:DcrStreamName            = $null
$script:TenantId                 = $null
$script:AppId                    = $null
$script:AppSecret                = $null
$script:CertificateSubject       = $null      # e.g. 'CN=DJMLog-Auth'
$script:CertificateThumbprint    = $null      # pin to specific cert
$script:FlushThreshold           = 100
$script:MaxBufferSize            = 5000
$script:MaxBufferBytes           = 52428800   # 50 MB byte-level cap on the buffer
$script:MaxFlushRetries          = 3
# Retained for back-compat with code paths that used $script:LogBuffer. v1.x
# tests still write through the legacy buffer fields; v2.0 LA buffer lives in
# the writer's $WriterShared.LABuffer.
$script:LogBuffer                = [System.Collections.Generic.List[hashtable]]::new()
$script:BufferByteTotal          = 0
$script:BearerToken              = $null
$script:BearerTokenExternal      = $null
$script:TokenExpiry              = [datetime]::MinValue
$script:FlushFailureCount        = 0
$script:AutoFlushDisabled        = $false
$script:AutoFlushOpenedAtUtc     = $null
$script:HalfOpenAfterSeconds     = 300

# Internal error queue (SelfLog) — last 100 errors, FIFO. Surfaced via Get-DJMLogDiagnostics.
$script:InternalErrors           = [System.Collections.Generic.Queue[pscustomobject]]::new()
$script:InternalErrorsMaxSize    = 100

# Legacy in-process semaphore retained for the v1.x $script:LogBuffer code path
# kept on the back-compat surface. The async writer's LA buffer is single-reader
# and does not need this.
$script:BufferLock               = [System.Threading.SemaphoreSlim]::new(1, 1)

# Named OS mutex shared across all runspaces on this machine.
$script:LogMutex                 = [System.Threading.Mutex]::new($false, 'DJMLog_WriteAccess')

# Dispose mutex + semaphore + writer when module is removed.
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    try { Stop-DJMWriter -TimeoutMs 2000 } catch { $null = $_ }
    if ($script:LogMutex)   { try { $script:LogMutex.Dispose() }   catch { $null = $_ } }
    if ($script:BufferLock) { try { $script:BufferLock.Dispose() } catch { $null = $_ } }
}

# Note: a previous draft registered a PowerShell.Exiting engine-event handler
# to flush + stop the writer on host shutdown. That introduced a race with the
# OnRemove handler above when both fired during script teardown and could leave
# the writer half-disposed. OnRemove is sufficient — Remove-Module fires it on
# normal teardown and the runspace exits without issue when the host process
# dies otherwise.

# Dot-source all private helpers then all public functions. Wrap each in
# try/catch so a single bad file leaves the module usable for the rest. Failures
# are queued in the SelfLog and re-thrown only if any FunctionsToExport entry
# can't be resolved after loading — we won't ship a half-loaded module.
$loadFailures = [System.Collections.Generic.List[string]]::new()
$privateFiles = @()
if (Test-Path "$PSScriptRoot\Private") {
    $privateFiles += Get-ChildItem -Path "$PSScriptRoot\Private" -Filter '*.ps1' -Recurse
}
$publicFiles = @()
if (Test-Path "$PSScriptRoot\Public") {
    $publicFiles += Get-ChildItem -Path "$PSScriptRoot\Public" -Filter '*.ps1'
}
foreach ($file in @($privateFiles + $publicFiles)) {
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
            [Console]::Error.WriteLine("DJMLog: failed to load $($file.Name) and could not enqueue SelfLog: $($_.Exception.Message)")
        }
    }
}

if ($loadFailures.Count -gt 0) {
    if (Test-Path -LiteralPath $script:ModuleManifestPath) {
        $manifest  = Import-PowerShellDataFile -LiteralPath $script:ModuleManifestPath
        $exports   = @($manifest.FunctionsToExport)
        $missing   = @($exports.Where({ -not (Get-Command -Name $_ -ErrorAction SilentlyContinue) }))
        if ($missing.Count -gt 0) {
            throw "DJMLog failed to load: missing exported functions [$($missing -join ', ')]. Failures: $($loadFailures -join '; ')"
        }
    }
    Write-Warning "DJMLog: $($loadFailures.Count) source file(s) failed to load but all exports resolved. See Get-DJMLogDiagnostics for details."
}

# Spawn the writer unless we're inside a writer-mode child runspace
# ($env:DJMLOG_WRITER_ROLE is reserved for diagnostic / future use; the current
# implementation does not re-import the module inside the writer).
if (-not $env:DJMLOG_WRITER_ROLE) {
    try { Start-DJMWriter; Update-DJMWriterShared } catch {
        $script:InternalErrors.Enqueue([pscustomobject]@{
            UtcTimestamp = [datetime]::UtcNow.ToString('o')
            Source       = 'Module Load'
            Message      = "Failed to start writer runspace: $($_.Exception.Message)"
            Exception    = $_.Exception
        })
    }
}
