# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

DJMLog is a PowerShell 7+ module (`DJMLog.psm1`) for structured JSONL logging in automation scripts. It is a single-file module with no build step — import it directly with `Import-Module`.

## Development Commands

```powershell
# Import the module for interactive testing
Import-Module ./DJMLog.psm1 -Force

# Run a quick smoke test
Set-DJMLogConfig -Path ./test.jsonl
Write-DJMLog -Level INFO -Message "Test entry"
Read-DJMLog -Path ./test.jsonl

# View exported functions
Get-Command -Module DJMLog

# Read inline help for any function
Get-Help Write-DJMLog -Full
Get-Help Read-DJMLog -Full
```

PowerShell 7+ is required. There is no test suite, build system, or linter configured in the repo.

## Architecture

Five exported functions in a single module file (`DJMLog.psm1`):

| Function | Role |
|---|---|
| `Set-DJMLogConfig` | Sets module-level defaults (path, max size, mutex timeout). Accepts direct params or a JSON config file. |
| `Write-DJMLog` | Appends a JSONL entry atomically using a named OS mutex (`DJMLog_WriteAccess`). Rotates the file when `MaxSizeMB` is exceeded. |
| `Read-DJMLog` | Streams a JSONL file line-by-line, filters by level/correlation/time/text, flattens nested metadata, and normalises all output objects to identical property sets. |
| `ConvertTo-DJMDictionary` | Converts a PSObject list or hashtable to `Dictionary[string, PSObject]` with lowercase keys. |
| `ConvertTo-DJMOrderedPSObject` | Converts an IDictionary to a PSCustomObject preserving key order. |

One private helper: `Expand-MetadataValue` — recursive flattener for nested metadata objects (underscore-separated key paths, e.g. `Error_ScriptName`).

### Key design points

- **Parallel safety**: `Write-DJMLog` acquires a named mutex before each append so multiple runspaces can write without file-lock contention. `MutexTimeoutMs` (default 2000 ms) controls how long to wait.
- **Log rotation**: when the file exceeds `MaxSizeMB`, it is renamed with a UTC timestamp suffix before a new file is started.
- **Metadata flattening**: `Read-DJMLog` recursively promotes nested metadata to top-level columns so output can be piped to `Export-Csv` or `Out-GridView` cleanly.
- **Column normalisation**: every object returned by `Read-DJMLog` carries the same property set (the union of all columns seen) so that `Format-Table` and CSV export produce consistent columns even when entries have different metadata shapes.

### Log entry JSON schema

```json
{
    "UtcTimestamp": "2026-03-01T12:34:56.789Z",
    "Level": "INFO | WARNING | ERROR | DEBUG | VERBOSE",
    "Message": "string",
    "CorrelationId": "guid-string",
    "Metadata": {
        "AnyKey": "AnyValue",
        "Error": {
            "ScriptName": "path",
            "LineNumber": 42,
            "Command": "string",
            "PositionMessage": "string",
            "Type": "ExceptionTypeName",
            "Message": "string"
        }
    }
}
```

### Config file format (JSON)

```json
{
    "Path": "C:\\Logs\\automation.jsonl",
    "MaxSizeMB": 50,
    "MutexTimeoutMs": 2000
}
```

Pass the config file path to `Set-DJMLogConfig -ConfigPath <file>`. Explicit parameters take precedence over config-file values.

## Module Structure

```
DJMLog/
├── DJMLog.psd1                          # Module manifest
├── DJMLog.psm1                          # Module loader — dot-sources Public/ + Private/
├── Public/                              # One .ps1 per exported function
│   ├── Set-DJMLogConfig.ps1
│   ├── Write-DJMLog.ps1
│   ├── Read-DJMLog.ps1
│   ├── ConvertTo-DJMDictionary.ps1
│   └── ConvertTo-DJMOrderedPSObject.ps1
├── Private/                             # Internal helpers
│   └── Expand-MetadataValue.ps1
├── tests/                               # Pester 5 test suite
│   ├── Set-DJMLogConfig.Tests.ps1
│   ├── Write-DJMLog.Tests.ps1
│   ├── Read-DJMLog.Tests.ps1
│   ├── ConvertTo-DJMDictionary.Tests.ps1
│   └── ConvertTo-DJMOrderedPSObject.Tests.ps1
├── PSScriptAnalyzerSettings.psd1        # Linter config
└── .github/workflows/ci.yml             # PSScriptAnalyzer + Pester on push/PR
```

Import via manifest: `Import-Module ./DJMLog.psd1 -Force`

## Development Commands

```powershell
# Import via manifest
Import-Module ./DJMLog.psd1 -Force

# Run PSScriptAnalyzer
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1

# Run Pester tests
Invoke-Pester ./tests/ -Output Detailed
```

## PowerShell House Rules

- **Language**: PowerShell 7+ only. No compatibility shims for Windows PowerShell 5.x.
- **Simplicity**: Never add unrequested functionality. Minimum complexity for the current task.
- **Iteration**: `foreach ($item in $collection)` — never `ForEach-Object` / `%`.
- **Filtering**: `.Where({ … })` with optional mode — never `Where-Object` / `?`.
- **Collections**: `ArrayList` (small/heterogeneous), `List[T]` (large/typed), `Dictionary[string,PSObject]` (lookups).
- **Memory**: `$var = $null` to release large temporaries; `Remove-Variable` for global/session cleanup.
- **Bulk data**: Retrieve only required properties; early-exit on empty sets before further processing.
- **Logging**: Minimal structured events compatible with `Write-DJMLog` JSONL format.
- **Functions**: `[CmdletBinding()]`, validated parameters, return objects not text.
- **Errors**: Throw only on unrecoverable failures; otherwise capture, log, and continue.
- **Help**: Synopsis, description, parameter docs, and at least one example on every public function.
- **Strict mode**: Never use `Set-StrictMode`.
- **Output in chat**: Always display PowerShell code as fenced code blocks. Never create a file unless explicitly requested.
- **Microsoft Learn MCP**: For any Microsoft product (PowerShell, Azure, Entra ID, AD, M365, Graph API, MSFT SDKs) — query the Microsoft Learn MCP tool first before relying on training knowledge for APIs, cmdlets, or product behavior.
