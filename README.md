# DJMLog

[![CI](https://github.com/chaospheremk/DJMLog/actions/workflows/ci.yml/badge.svg)](https://github.com/chaospheremk/DJMLog/actions/workflows/ci.yml)
[![Docs](https://github.com/chaospheremk/DJMLog/actions/workflows/docs.yml/badge.svg)](https://github.com/chaospheremk/DJMLog/actions/workflows/docs.yml)

A PowerShell 7+ module for structured JSONL logging in automation scripts.

DJMLog provides atomic, mutex-protected file writes, automatic log rotation, metadata flattening for clean CSV/grid output, and optional buffered ingestion to Azure Log Analytics via the Logs Ingestion API.

**[Documentation](https://chaospheremk.github.io/DJMLog/)**

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

# Write with metadata
Write-DJMLog -Level INFO -Message "Processing item" -Metadata @{
    ItemId   = "ABC-123"
    BatchNum = 5
}

# Read and filter log entries
Read-DJMLog -Path ./automation.jsonl -Level ERROR
```

## Features

- **Atomic writes** — named OS mutex prevents file-lock contention across parallel runspaces
- **Log rotation** — automatic file rotation by size (`MaxSizeMB`) or schedule (Daily/Weekly/Monthly) with configurable retention policies
- **Min-level filtering** — `MinLevel` threshold silently drops entries below the configured severity
- **Caller auto-capture** — automatically records the calling script and line number in each log entry (enabled by default)
- **Structured metadata** — nested metadata is flattened to top-level columns for `Export-Csv` and `Out-GridView`
- **Correlation tracking** — group related log entries with a shared correlation ID
- **Azure Log Analytics** — optional buffered ingestion via the DCR-based Logs Ingestion API (Commercial, GCCHigh, DoD)

## Commands

| Command | Description |
|---|---|
| `Set-DJMLogConfig` | Configure module-level defaults (path, max size, Log Analytics integration) |
| `Write-DJMLog` | Append a structured JSONL entry with atomic file locking |
| `Read-DJMLog` | Read and filter a JSONL log file with metadata flattening |
| `Send-DJMLogBuffer` | Flush the in-memory buffer to Azure Log Analytics |
| `ConvertTo-DJMDictionary` | Convert PSObjects or a hashtable to a typed dictionary |
| `ConvertTo-DJMOrderedPSObject` | Convert a dictionary to a PSCustomObject preserving key order |

See the [command reference](https://chaospheremk.github.io/DJMLog/commands/) for full documentation.

## Log Entry Format

Each call to `Write-DJMLog` appends a single JSON line:

```json
{
    "UtcTimestamp": "2026-03-01T12:34:56.789Z",
    "Level": "INFO",
    "Message": "User provisioned",
    "CorrelationId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "Metadata": {
        "UserPrincipalName": "jsmith@contoso.com",
        "Department": "Engineering",
        "Caller": {
            "ScriptName": "C:\\Scripts\\Provision-User.ps1",
            "LineNumber": 42
        }
    }
}
```

## Requirements

- PowerShell 7.0 or later
- Azure Log Analytics integration requires an Entra ID app registration with appropriate permissions
