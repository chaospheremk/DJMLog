# Code Session — `DJMLog Structured Logging Module`

## Architecture

One function per file: 11 exported functions in `Public/`, 13 private helpers in
`Private/` (`../key-facts.md` keeps the full inventory). Core entry points:

- `Set-DJMLogConfig` — module defaults and sinks; direct params or a JSON config file
- `Write-DJMLog` — enqueues an entry for the async writer runspace (ADR-019)
- `Read-DJMLog` — streams, filters, and flattens a JSONL log
- `Flush-DJMLog` / `Wait-DJMLog` — fence the writer queue (`Send-DJMLogBuffer` is a back-compat wrapper)
- `Get-DJMLogDiagnostics` — writer state and SelfLog errors

### Key design points

- **Parallel safety**: the writer runspace acquires the named OS mutex `DJMLog_WriteAccess` before each file append, so multiple processes can write the same file without lock contention. `MutexTimeoutMs` (default 2000 ms) controls how long to wait.
- **Log rotation**: when the file exceeds `MaxSizeMB` or the configured `RotationSchedule` (Daily/Weekly/Monthly) triggers, the file is renamed with a UTC timestamp suffix before a new file is started.
- **Min-level filtering**: `MinLevel` (DEBUG < INFO < WARN < ERROR) controls the minimum severity written; entries below the threshold are silently dropped.
- **Retention policies**: `RetainDays` and `RetainFiles` automatically clean up old rotated log files.
- **Caller auto-capture**: when `IncludeCaller` is `$true` (the default), each entry's Metadata includes the calling script path and line number.
- **Azure Log Analytics integration**: optional buffered ingestion via the Logs Ingestion API (DCR-based REST). Entries are buffered in-memory and flushed in batches. Supports Commercial, GCCHigh, and DoD cloud environments (default GCCHigh). Auth, in priority order: pre-acquired bearer token → managed identity (IMDS) → certificate JWT assertion → client secret. Circuit breaker disables auto-flush after consecutive failures.
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
├── Public/                              # One .ps1 per exported function (11)
├── Private/                             # One .ps1 per internal helper (13)
├── tests/                               # Pester 5 suite, one .Tests.ps1 per function + StressTests/
├── scripts/                             # Git hooks installer, stress drill, Invoke-WithDJMHostExit wrapper
├── PSScriptAnalyzerSettings.psd1        # Linter config
└── .github/workflows/
    ├── ci.yml                           # PSScriptAnalyzer + Pester on PR
    ├── release.yml                      # Tag-triggered ACR publish + GitHub Release
    ├── docs.yml                         # Zensical docs build + GitHub Pages deploy
    ├── pre-commit-update.yml            # Scheduled pre-commit hook version bumps
    └── sync-dev.yml                     # Auto-merge main into dev
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
Invoke-Build Release -Configuration Release -Version 1.2.3  # Full release pipeline
Invoke-Build ?                         # Show all tasks and dependencies

# Install pre-push hook (one-time)
./scripts/Install-GitHooks.ps1

# Direct tool access (when not using Invoke-Build)
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
Invoke-Pester ./tests/ -Output Detailed
```
