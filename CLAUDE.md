# Code Session — `DJMLog Structured Logging Module`

## Context

This is the code repository for the `DJMLog Structured Logging Module` vault project.
Vault memory files are one level up in the parent directory:

- ../bugs.md        — known issues and solutions; check before debugging
- ../decisions.md   — decisions made; check before proposing changes
- ../key-facts.md   — project configuration reference
- ../issues.md      — work log

The vault session that manages planning and note-taking runs from the
vault root. This code session runs from this directory only.

## On Startup

1. Read ../decisions.md
2. Read ../bugs.md
3. Read ../key-facts.md
4. Run `git status` — report any untracked or modified files and offer to commit them via PR

## Memory Protocols

**During the session, watch for:**

- Configuration patterns, parameter conventions, or environment facts worth keeping as reference — prompt to add to ../key-facts.md
- Learnings that are broadly reusable beyond this project — flag them so the vault session can promote them to resource notes
- Decisions being made conversationally that haven't been logged — prompt to add to ../decisions.md before the session ends

Before proposing a technical approach: read ../decisions.md
Before debugging: read ../bugs.md
After fixing a bug: append to ../bugs.md using the standard format
After making a technical decision: append to ../decisions.md as an ADR
After completing a work block: append to ../issues.md

## Rules

- Read ../../../_meta/security.md before writing any code
- Read ../../../_meta/powershell-housestyle.md before writing any PowerShell
- Read ../../../_meta/graph-api-skills.md before writing any Graph API code
- No real IDs, hostnames, credentials, or org-identifying content — ever
- All parameters use placeholders: `<tenant-id>` `<subscription-id>` etc.
- Never modify files outside this code/ folder except the four memory files
  (../bugs.md, ../decisions.md, ../key-facts.md, ../issues.md)
- Never make claims about code or APIs before investigating. Cite source file and line for every claim. It is acceptable and preferred to say you are uncertain.

## GitHub

This folder is its own git repository.
Push directly to this project's GitHub remote.
Do not use the vault's 50-Outputs/ for this project's code.

## Architecture

Six exported functions across individual files in `Public/`:

| Function | Role |
|---|---|
| `Set-DJMLogConfig` | Sets module-level defaults (path, max size, mutex timeout, min level, rotation schedule, retention policies, caller auto-capture, Log Analytics integration). Accepts direct params or a JSON config file. |
| `Write-DJMLog` | Appends a JSONL entry atomically using a named OS mutex (`DJMLog_WriteAccess`). Rotates the file when `MaxSizeMB` is exceeded or on schedule. Skips entries below `MinLevel`. Auto-captures caller info when `IncludeCaller` is enabled. Optionally buffers entries for Azure Log Analytics. |
| `Read-DJMLog` | Streams a JSONL file line-by-line, filters by level/correlation/time/text, flattens nested metadata, and normalises all output objects to identical property sets. |
| `Send-DJMLogBuffer` | Flushes the in-memory log buffer to Azure Log Analytics via the Logs Ingestion API (DCR-based). Chunks batches to 500 KB. |
| `ConvertTo-DJMDictionary` | Converts a PSObject list or hashtable to `Dictionary[string, PSObject]` with lowercase keys. |
| `ConvertTo-DJMOrderedPSObject` | Converts an IDictionary to a PSCustomObject preserving key order. |

Two private helpers:
- `Expand-MetadataValue` — recursive flattener for nested metadata objects (underscore-separated key paths, e.g. `Error_ScriptName`).
- `Get-DJMBearerToken` — OAuth2 client_credentials token acquisition + caching (cert JWT assertion or client secret). Cloud-aware (Commercial, GCCHigh, DoD).

### Key design points

- **Parallel safety**: `Write-DJMLog` acquires a named mutex before each append so multiple runspaces can write without file-lock contention. `MutexTimeoutMs` (default 2000 ms) controls how long to wait.
- **Log rotation**: when the file exceeds `MaxSizeMB` or the configured `RotationSchedule` (Daily/Weekly/Monthly) triggers, the file is renamed with a UTC timestamp suffix before a new file is started.
- **Min-level filtering**: `MinLevel` (DEBUG < INFO < WARN < ERROR) controls the minimum severity written; entries below the threshold are silently dropped.
- **Retention policies**: `RetainDays` and `RetainFiles` automatically clean up old rotated log files.
- **Caller auto-capture**: when `IncludeCaller` is `$true` (the default), each entry's Metadata includes the calling script path and line number.
- **Azure Log Analytics integration**: optional buffered ingestion via the Logs Ingestion API (DCR-based REST). Entries are buffered in-memory and flushed in batches. Supports Commercial, GCCHigh, and DoD cloud environments (default GCCHigh). Auth: certificate JWT assertion, client secret, or pre-acquired bearer token. Circuit breaker disables auto-flush after consecutive failures.
- **Metadata flattening**: `Read-DJMLog` recursively promotes nested metadata to top-level columns so output can be piped to `Export-Csv` or `Out-GridView` cleanly.
- **Column normalisation**: every object returned by `Read-DJMLog` carries the same property set (the union of all columns seen) so that `Format-Table` and CSV export produce consistent columns even when entries have different metadata shapes.

### Log entry JSON schema

```json
{
    "UtcTimestamp": "2026-03-01T12:34:56.789Z",
    "Level": "INFO | WARN | ERROR | DEBUG",
    "Message": "string",
    "CorrelationId": "guid-string",
    "Metadata": {
        "AnyKey": "AnyValue",
        "Caller": {
            "ScriptName": "path",
            "LineNumber": 10
        },
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
    "MutexTimeoutMs": 2000,
    "MinLevel": "INFO",
    "RotationSchedule": "Daily",
    "RetainDays": 30,
    "RetainFiles": 10,
    "IncludeCaller": true,
    "LogAnalyticsEnabled": true,
    "CloudEnvironment": "GCCHigh",
    "DcrEndpointUri": "<dce-endpoint-uri>",
    "DcrImmutableId": "<dcr-immutable-id>",
    "DcrStreamName": "<dcr-stream-name>",
    "TenantId": "<tenant-id>",
    "AppId": "<app-id>",
    "CertificateSubject": "<certificate-subject>",
    "FlushThreshold": 100,
    "MaxBufferSize": 5000,
    "MaxFlushRetries": 3
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
│   ├── Send-DJMLogBuffer.ps1
│   ├── ConvertTo-DJMDictionary.ps1
│   └── ConvertTo-DJMOrderedPSObject.ps1
├── Private/                             # Internal helpers
│   ├── Expand-MetadataValue.ps1
│   └── Get-DJMBearerToken.ps1
├── tests/                               # Pester 5 test suite
│   ├── Set-DJMLogConfig.Tests.ps1
│   ├── Write-DJMLog.Tests.ps1
│   ├── Read-DJMLog.Tests.ps1
│   ├── Send-DJMLogBuffer.Tests.ps1
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

# Invoke-Build tasks (preferred — matches CI)
Invoke-Build Build                     # Full pipeline: Clean → Lint → Test → Docs
Invoke-Build Lint                      # PSScriptAnalyzer only
Invoke-Build Test                      # Pester only (unit, no coverage)
Invoke-Build Test -Configuration Release  # Pester with coverage + threshold check
Invoke-Build Docs                      # Regenerate PlatyPS docs in docs/commands/
Invoke-Build AssertDocsClean           # Verify committed docs match fresh generation
Invoke-Build BumpVersion               # Increment patch version in manifest
Invoke-Build Pack                      # Assemble output/ directory
Invoke-Build ?                         # Show all tasks and dependencies

# Install pre-push hook (one-time)
./scripts/Install-GitHooks.ps1

# Direct tool access (when not using Invoke-Build)
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
Invoke-Pester ./tests/ -Output Detailed
```
