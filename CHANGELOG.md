# Changelog

All notable changes to DJMLog are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [1.0.0] - 2026-03-08

### Added

- `Set-DJMLogConfig` — configure module-level defaults (path, max size, mutex timeout, min level, rotation schedule, retention policies, caller capture, Log Analytics integration)
- `Write-DJMLog` — append a structured JSONL entry with atomic mutex-protected file locking
- `Read-DJMLog` — stream and filter JSONL log files with metadata flattening and column normalization
- `Send-DJMLogBuffer` — flush in-memory log buffer to Azure Log Analytics via DCR-based Logs Ingestion API
- `ConvertTo-DJMDictionary` — convert PSObject list or hashtable to typed dictionary with lowercase keys
- `ConvertTo-DJMOrderedPSObject` — convert dictionary to PSCustomObject preserving key order
- Named OS mutex (`DJMLog_WriteAccess`) for parallel write safety across runspaces
- MinLevel filtering with level hierarchy (DEBUG < INFO < WARN < ERROR)
- Time-based log rotation (`Daily` / `Hourly`) alongside size-based rotation
- Retention policies (`RetainDays` / `RetainFiles`) for automatic rotated log cleanup
- Caller auto-capture (script name and line number in each log entry, enabled by default)
- Azure Log Analytics integration via DCR-based Logs Ingestion API with circuit breaker
- Support for Commercial, GCC High, and DoD cloud environments (default GCC High)
- JSON config file support (`Set-DJMLogConfig -ConfigPath`)
- Metadata flattening for clean `Export-Csv` and `Out-GridView` output
- Column normalization across entries with different metadata shapes
- 170 Pester tests with full code coverage
- CI pipeline (PSScriptAnalyzer, Pester with JaCoCo coverage, TruffleHog secret scan, path-based filtering)
- PlatyPS command reference documentation with GitHub Pages deployment
- README with badges, quick start, and command reference link
- Dark theme (slate/indigo/teal) with Roboto fonts

### Changed

- CI/CD standardized to cross-project template (ci-gate, test-reporter, gitleaks, module caching)
- Docs pipeline migrated from MkDocs Material to Zensical (v0.0.27)
