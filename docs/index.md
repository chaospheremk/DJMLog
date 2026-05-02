# DJMLog

A PowerShell 7.6+ module for asynchronous structured JSONL logging in automation scripts.

DJMLog v2.0 ships an async writer architecture: `Write-DJMLog` validates → enriches → redacts → enqueues onto a bounded `System.Threading.Channels.Channel`, and a dedicated writer runspace fans entries out across the enabled sinks (File / Console / EventLog / LogAnalytics). The producer-side hot path is ~10 µs regardless of file rotation cost or Log Analytics flush activity.

## Installation

```powershell
Import-Module ./DJMLog.psd1 -Force
```

## Quick Start

```powershell
# Configure the log file path
Set-DJMLogConfig -Path ./automation.jsonl

# Write a structured log entry
Write-DJMLog -Level INFO -Message "Job started"

# Write with metadata (sensitive values are redacted automatically)
Write-DJMLog -Level INFO -Message "Processing item" -Metadata @{
    ItemId   = "ABC-123"
    BatchNum = 5
    ApiKey   = $someSecret    # auto-redacted by key name
}

# Wrap a unit of work in an activity — child entries inherit the
# CorrelationId, ActivityId, and ParentActivityId
Start-DJMActivity -Name 'SyncTenantUsers'
try {
    Write-DJMLog -Message 'Sync started'
    # ... work ...
    Write-DJMLog -Message 'Sync completed'
}
finally {
    Stop-DJMActivity
}

# Drain pending entries before reading the file or exiting the script
[void](Flush-DJMLog -TimeoutSec 5)

# Read and filter log entries (auto-detects schema v1 vs v2)
Read-DJMLog -LogPath ./automation.jsonl -Level ERROR
```

!!! warning "Asynchronous by default"
    Write-DJMLog returns immediately after enqueueing; the file write is asynchronous. Always call `Flush-DJMLog` before reading the file in the same script. Tests and tools that need v1.x synchronous semantics can opt-in via `$env:DJMLOG_SYNC_WRITES = '1'`.

## Features

- **Async writer architecture** — bounded channel + dedicated writer runspace; producer-side latency ~10 µs regardless of file or Log Analytics activity
- **Multi-sink fan-out** — `File` / `Console` / `EventLog` / `LogAnalytics` selectable via `Set-DJMLogConfig -Sinks`
- **Schema v2** — `SchemaVersion`, OTel `SeverityNumber` (1–24), `Host` enrichment, `ActivityId` / `ParentActivityId` / `ActivityName`. Read-DJMLog auto-detects v1 files
- **Activities + W3C Trace Context** — `Start-DJMActivity` / `Stop-DJMActivity` for nested operation scopes; picks up `[System.Diagnostics.Activity]::Current` into `Metadata.Trace`
- **Redaction** — always-on for `[SecureString]` / `[PSCredential]` / sensitive-key matches; configurable regex patterns and presets (`Email` / `BearerToken` / `CreditCard`)
- **Sampling** — per-level rates: `Set-DJMLogConfig -SampleRate @{ DEBUG = 0.01; INFO = 0.1 }`
- **Atomic writes** — named OS mutex coordinates appends across runspaces
- **Log rotation + retention** — by size or schedule (`Daily` / `Hourly`) with `RetainDays` / `RetainFiles` cleanup
- **Streaming reads** — `Read-DJMLog -Stream` emits entries to the pipeline as they're parsed; constant memory regardless of file size
- **Azure Log Analytics** — buffered DCR ingestion (Commercial / GCCHigh / DoD) with gzip + 950 KB chunking, `Retry-After`-aware retries, and a half-open circuit breaker

See the [command reference](commands/index.md) for full documentation of all 11 cmdlets.
