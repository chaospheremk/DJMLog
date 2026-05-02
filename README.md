# DJMLog

[![CI](https://github.com/chaospheremk/DJMLog/actions/workflows/ci.yml/badge.svg)](https://github.com/chaospheremk/DJMLog/actions/workflows/ci.yml)
[![Docs](https://github.com/chaospheremk/DJMLog/actions/workflows/docs.yml/badge.svg)](https://github.com/chaospheremk/DJMLog/actions/workflows/docs.yml)

A PowerShell 7+ module for asynchronous structured JSONL logging in automation scripts.

DJMLog v2.0 ships an async writer architecture: `Write-DJMLog` validates → enriches → redacts → enqueues onto a bounded `System.Threading.Channels.Channel`, and a dedicated writer runspace fans entries out across the enabled sinks (File / Console / EventLog / LogAnalytics). The producer-side hot path is ~10 µs regardless of file rotation cost or Log Analytics flush activity.

**[Documentation](https://chaospheremk.github.io/DJMLog/)** | **[Changelog](CHANGELOG.md)**

## Installation

Clone the repository and import the module:

```powershell
git clone https://github.com/chaospheremk/DJMLog.git
Import-Module ./DJMLog/DJMLog.psd1 -Force
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

> **Note** — Write-DJMLog returns immediately after enqueueing; the file write is asynchronous. Always call `Flush-DJMLog` before reading the file in the same script. Tests and tools that need v1.x synchronous semantics can opt-in via `$env:DJMLOG_SYNC_WRITES = '1'`.

## Features

- **Async writer architecture** — bounded channel + dedicated writer runspace; producer-side latency ~10 µs regardless of file or Log Analytics activity
- **Multi-sink fan-out** — one entry routes to any combination of `File` / `Console` / `EventLog` / `LogAnalytics` via `Set-DJMLogConfig -Sinks`
- **Schema v2** — every entry carries `SchemaVersion`, `SeverityNumber` (OTel 1–24), `Host` enrichment, and (when an activity is in scope) `ActivityId` / `ParentActivityId` / `ActivityName`. Auto-detected back-compat read of v1 files
- **Activities + W3C Trace Context** — `Start-DJMActivity` / `Stop-DJMActivity` for nested operation scopes; `[System.Diagnostics.Activity]::Current` is picked up automatically into `Metadata.Trace`
- **Redaction** — always-on for `[SecureString]` / `[PSCredential]` and metadata keys matching `(?i)password|secret|token|apikey`; configurable via `-RedactionPatterns` regex array and `-RedactionPresets ('Email','BearerToken','CreditCard')`
- **Sampling** — per-level rates: `Set-DJMLogConfig -SampleRate @{ DEBUG = 0.01; INFO = 0.1 }`. Applied after MinLevel filtering, before the channel write
- **Atomic writes** — named OS mutex (`DJMLog_WriteAccess`) coordinates file appends across runspaces; rotation decisions happen inside the mutex
- **Log rotation + retention** — by size (`MaxSizeMB`) or schedule (`Daily` / `Hourly`) with `RetainDays` / `RetainFiles` cleanup
- **Streaming reads** — `Read-DJMLog -Stream` emits entries to the pipeline as they're parsed; constant memory regardless of file size
- **SelfLog diagnostics** — `Get-DJMLogDiagnostics` returns the writer's internal error queue, channel stats (Enqueued / Processed / Dropped / Queued counts), and the Log Analytics circuit-breaker state
- **Azure Log Analytics** — buffered ingestion via the DCR-based Logs Ingestion API (Commercial / GCCHigh / DoD). `Flush-DJMLog` triggers an immediate flush; gzip + 950 KB pre-compression chunking; half-open circuit breaker with `Retry-After`-aware retries on 429/5xx

## Commands

| Command | Description |
|---|---|
| `Set-DJMLogConfig` | Configure module-level defaults: path, sinks, channel capacity, rotation, redaction, sampling, Log Analytics |
| `Write-DJMLog` | Submit a structured entry to the async writer for fan-out across the configured sinks |
| `Read-DJMLog` | Read and filter a JSONL file with metadata flattening and schema v1/v2 auto-detect |
| `Flush-DJMLog` | Drain the writer channel and (if Log Analytics is enabled) trigger an immediate flush |
| `Wait-DJMLog` | Block until the writer channel has drained, with a mandatory timeout |
| `Start-DJMActivity` | Push an activity scope onto the per-runspace activity stack |
| `Stop-DJMActivity` | Pop an activity scope and emit a duration entry |
| `Send-DJMLogBuffer` | Back-compat wrapper over `Flush-DJMLog` |
| `Get-DJMLogDiagnostics` | Surface the SelfLog error queue, channel stats, and circuit-breaker state |
| `ConvertTo-DJMDictionary` | Convert PSObjects or a hashtable to a typed dictionary |
| `ConvertTo-DJMOrderedPSObject` | Convert a dictionary to a PSCustomObject preserving key order |

See the [command reference](https://chaospheremk.github.io/DJMLog/commands/) for full documentation.

## Log Entry Format (Schema v2)

Each call to `Write-DJMLog` enqueues a single JSON line; the writer appends to the configured file:

```json
{
    "SchemaVersion": "2",
    "UtcTimestamp": "2026-04-28T12:34:56.7891234Z",
    "Level": "INFO",
    "SeverityNumber": 9,
    "Message": "User provisioned",
    "CorrelationId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "ActivityId": "11111111-2222-3333-4444-555555555555",
    "ParentActivityId": null,
    "ActivityName": "ProvisionUser",
    "Host": {
        "MachineName": "WORKER-01",
        "ProcessId": 1234,
        "UserName": "svc-automation",
        "PSVersion": "7.6.0"
    },
    "Metadata": {
        "UserPrincipalName": "jsmith@contoso.com",
        "Department": "Engineering",
        "ApiKey": "[REDACTED]",
        "Trace": {
            "TraceId": "...",
            "SpanId": "..."
        },
        "Caller": {
            "ScriptName": "C:\\Scripts\\Provision-User.ps1",
            "LineNumber": 42
        }
    }
}
```

`Read-DJMLog` auto-detects v1 entries (no `SchemaVersion` field) and back-fills `SeverityNumber` from the `Level` string, so v1 logs continue to read cleanly under v2.

## Migrating from v1.x to v2.0

- **Write-DJMLog is now asynchronous.** Scripts that depended on synchronous on-disk durability must call `Flush-DJMLog` before reading the file. Test scenarios can opt back into synchronous semantics via `$env:DJMLOG_SYNC_WRITES = '1'`.
- **Schema v2 is emitted by default.** v1-only consumers continue to work because v2 is a strict superset, but parsers that match exact field sets need updating.
- **`Send-DJMLogBuffer` no longer flushes in the caller's runspace.** It forwards to `Flush-DJMLog`. Tests that mocked `Invoke-RestMethod` in the main scope to assert flush behaviour need to migrate.
- **Certificate-auth (JWT assertion) Log Analytics flush** runs in the writer runspace alongside `AppSecret` and `BearerTokenExternal`. The cert is resolved in the main runspace at `Set-DJMLogConfig` time and the resolved `X509Certificate2` is marshalled into the writer; JWT signing happens inside the writer (ADR-027).
- **Managed identity (IMDS)** is the recommended replacement for the deprecated string `AppSecret`. Pass `-UseManagedIdentity` to `Set-DJMLogConfig` (system-assigned MI) or add `-ManagedIdentityClientId <guid>` for a user-assigned MI. The MI must hold the `Monitoring Metrics Publisher` role on the DCR. ADR-029.
- **String `AppSecret` is deprecated.** Set-DJMLogConfig still accepts a plain-string secret for back-compat but emits a deprecation warning. Pass `[SecureString]` or migrate to `-UseManagedIdentity`.
- **`Get-DJMLogDiagnostics` adds fields**: `EnqueuedCount` / `ProcessedCount` / `DroppedCount` / `QueuedCount`. Existing consumers reading `Errors` / `CircuitBreakerState` / `AutoFlushOpenedAtUtc` continue to work.

## Requirements

- PowerShell 7.0 or later (CI validates against 7.5; runs on 7.6)
- Azure Log Analytics integration requires an Entra ID app registration with appropriate permissions on a Data Collection Rule (DCR)
