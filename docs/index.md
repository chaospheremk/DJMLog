# DJMLog

A PowerShell 7+ module for structured JSONL logging in automation scripts. DJMLog provides atomic, mutex-protected file writes, automatic log rotation, metadata flattening for clean CSV/grid output, and optional buffered ingestion to Azure Log Analytics via the Logs Ingestion API.

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
- **Log rotation** — automatic file rotation when size exceeds the configured threshold
- **Structured metadata** — nested metadata is flattened to top-level columns for `Export-Csv` and `Out-GridView`
- **Azure Log Analytics** — optional buffered ingestion via the DCR-based Logs Ingestion API (Commercial, GCCHigh, DoD)
