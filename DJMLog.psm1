<#
.SYNOPSIS
Structured JSONL logging module for PowerShell 7.6+ (v2.0 — async writer + sinks).

.DESCRIPTION
Module loader. Initialises shared state, dot-sources private helpers and public
functions, then spawns the async writer runspace (per ADR-019).

Exports eleven functions:
  Set-DJMLogConfig, Write-DJMLog, Read-DJMLog, Send-DJMLogBuffer,
  Flush-DJMLog, Wait-DJMLog, Start-DJMActivity, Stop-DJMActivity,
  Get-DJMLogDiagnostics, ConvertTo-DJMDictionary, ConvertTo-DJMOrderedPSObject

.NOTES
Requires PowerShell 7.6 or later.
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
$script:WriterTask               = $null

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

# Module-removal cleanup. Do NOT call Stop-DJMWriter or otherwise tear down
# the writer here — under repeated Import-Module -Force cycles (which Pester
# does on every test file's BeforeAll) the dispose path leaks a foreground
# pipeline thread, which then keeps the host process alive after the script
# finishes (CI-observed: ~19 min hang per run before GitHub cancels). Instead
# we soft-cancel the writer's CancellationTokenSource and let the writer
# thread (already marked IsBackground via reflection in Start-DJMWriter) exit
# in the background.
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    try { if ($script:WriterCts) { $script:WriterCts.Cancel() } } catch { $null = $_ }
    try { if ($script:WriterChannel) { [void]$script:WriterChannel.Writer.TryComplete() } } catch { $null = $_ }
    if ($script:LogMutex)   { try { $script:LogMutex.Dispose() }   catch { $null = $_ } }
    if ($script:BufferLock) { try { $script:BufferLock.Dispose() } catch { $null = $_ } }
}

# Process-exit shutdown — without a hook here, the writer runspace's
# foreground pipeline thread keeps pwsh.exe alive indefinitely after the main
# script finishes (CI observation: pwsh subprocess hung ~19 min after the
# Test task returned until GitHub Actions cancelled the job).
#
# AppDomain.ProcessExit fires on host shutdown but runs on a thread that has
# no PowerShell runspace, so a PowerShell scriptblock cast to EventHandler
# throws "There is no Runspace available". We compile a tiny C# helper whose
# static method does the cleanup using a holder that the module populates,
# bypassing the runspace requirement entirely.
if (-not ('DJMLog.WriterShutdown' -as [type])) {
    Add-Type -TypeDefinition @'
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Threading;
using System.Threading.Tasks;
namespace DJMLog {
    public static class WriterRunner {
        // Run the writer's PowerShell instance synchronously on a thread-pool
        // worker. Thread-pool threads are background, so they do not block
        // pwsh.exe shutdown when the user's script finishes.
        public static Task Run(PowerShell ps) {
            return Task.Run(() => {
                try { ps.Invoke(); }
                catch { /* exceptions surface via ps.Streams.Error */ }
            });
        }
    }
    public static class WriterShutdown {
        // Set by Start-DJMWriter; the static Hook is registered on
        // AppDomain.ProcessExit at module load. On host shutdown we cancel,
        // complete the channel, briefly wait for the writer task, then
        // dispose the PowerShell + Runspace so the .NET host can finalise.
        public static CancellationTokenSource Cts;
        public static System.Threading.Channels.ChannelWriter<object> Writer;
        public static Task WriterTask;
        public static PowerShell PS;
        public static Runspace Rs;
        public static void Hook(object sender, System.EventArgs e) {
            // Keep this fast — the AppDomain.ProcessExit hook runs in-band
            // during Environment.Exit and blocks process termination until
            // it returns. PowerShell.Stop/Dispose can block on internal
            // pipeline state and have caused 19+ minute hangs in CI.
            // Just signal cancellation so the writer thread (if still alive)
            // exits on its own; the process is shutting down anyway.
            try { if (Cts    != null) Cts.Cancel(); }        catch { }
            try { if (Writer != null) Writer.TryComplete(); } catch { }
        }
    }
}
'@ -ReferencedAssemblies @(
        'System.Management.Automation',
        'System.Threading.Channels'
    )
    [System.AppDomain]::CurrentDomain.add_ProcessExit(
        [System.EventHandler][DJMLog.WriterShutdown]::Hook)
}

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
        # Roll back any partial state so the next Start-DJMWriter call (or a
        # Stop-DJMWriter from cleanup) doesn't trip on inconsistent fields.
        try { Stop-DJMWriter -TimeoutMs 500 } catch { $null = $_ }
    }
}
