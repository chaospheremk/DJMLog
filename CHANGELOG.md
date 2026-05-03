# Changelog

All notable changes to DJMLog are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- **Certificate auth in writer-runspace LA flush (ADR-027).** `Set-DJMLogConfig -CertificateThumbprint` and `-CertificateSubject` now drive end-to-end LA flush from the writer runspace. The cert is resolved in the main runspace at config time (only place `Cert:` PSDrive is reachable); the resolved `X509Certificate2` is marshalled into the writer; JWT signing happens inside the writer via the new `New-DJMJwtAssertion` private helper. Closes the ADR-025 negative consequence — callers no longer need to drop to main-runspace `Send-DJMLogBuffer -Force` for cert auth. PR #53.
- **Managed identity (IMDS) for LA auth (ADR-029).** New `Set-DJMLogConfig -UseManagedIdentity` switch and `-ManagedIdentityClientId` parameter for system-assigned and user-assigned MI respectively. Native HTTP against `http://169.254.169.254/metadata/identity/oauth2/token` (no Az.Accounts / Azure.Identity SDK dependency); priority 2 in the auth resolver, after `BearerTokenExternal` and before cert / secret. Cloud resource map: Commercial → `https://monitor.azure.com`; GCCHigh / DoD → `https://monitor.azure.us`. Delivers the ADR-015 deprecation-cycle replacement. PR #55.
- **`scripts/Invoke-WithDJMHostExit.ps1` helper (ADR-030).** Single source of truth for the BUG-023 / ADR-026 wrapper rationale. Accepts `-Script` as either a `[scriptblock]` (call-site form) or a `[string]` (`pwsh -File` fallback). On success: `[System.Environment]::Exit(($LASTEXITCODE ?? 0))`. On exception: writes the error and exits 1. Replaces the four copy-pasted `try/catch` + `[Environment]::Exit` blocks in `.github/workflows/ci.yml`, `.github/workflows/docs.yml`, `.github/workflows/release.yml`, and `scripts/Invoke-StressDrill.ps1`. PR #56.

### Changed

- **String `AppSecret` emits a deprecation `Write-Warning` (ADR-029).** When `Set-DJMLogConfig -AppSecret` is called with a non-empty plain `[string]`, the cmdlet warns and points callers at `[SecureString]` or `-UseManagedIdentity`. `[SecureString]` input remains warning-free. Back-compat preserved.
- **CI matrix narrowed to PowerShell 7.5 (ADR-028).** PS 7.4 dropped from CI; 7.6 bump deferred until `mcr.microsoft.com/powershell:7.6-ubuntu-22.04` ships (no `preview-` prefix) and `ubuntu-latest` ships pwsh ≥ 7.6 by default. Manifest `PowerShellVersion` stays at `7.0` — the module does not use any 7.5+ API. PR #54.
- **`Stop-DJMWriter` comment block trimmed (ADR-030).** The 11-line soft-stop / hard-stop history shrunk to a 5-line summary that points at `scripts/Invoke-WithDJMHostExit.ps1` for the rationale.

### Deferred

- **Logs Ingestion CI gate enablement (ADR-031).** The advisory `Logs Ingestion Integration` job in `ci.yml` (lines 225-301) stays `continue-on-error: true` until a real consumer ships LA sink usage. Operational checklist preserved in `issues.md`.

## [2.0.0] - 2026-04-26

Major release. Async writer architecture, multi-sink fan-out, schema v2,
activities, redaction, sampling. **Breaking changes** are listed below;
schema v2 is a strict superset of v1, and `Read-DJMLog` auto-detects v1
files for back-compat.

### Added

- **Async writer architecture (ADR-019).** `Write-DJMLog` validates → samples →
  enriches → redacts → enqueues onto `System.Threading.Channels.Channel<object>`
  (BoundedChannel, DropOldest, default capacity 10 000). A dedicated writer
  runspace drains the channel and fans out to enabled sinks. Producer-side
  hot path is ~10 µs.
- **Multi-sink fan-out (ADR-020).** `File`, `Console`, `EventLog`,
  `LogAnalytics` sinks selectable via `Set-DJMLogConfig -Sinks`.
- **Activities + W3C Trace Context (ADR-021).** New `Start-DJMActivity` /
  `Stop-DJMActivity` cmdlets push/pop frames on a per-runspace activity
  stack; nested activities inherit `ParentId` and emit duration entries on
  pop. Picks up `[System.Diagnostics.Activity]::Current` into
  `Metadata.Trace { TraceId, SpanId }`.
- **Schema v2 (ADR-022).** New entry fields: `SchemaVersion = "2"`,
  `SeverityNumber` (OTel 1–24: DEBUG=5 / INFO=9 / WARN=13 / ERROR=17 /
  FATAL=21), `Host` (`MachineName` / `ProcessId` / `UserName` / `PSVersion`),
  `ActivityId` / `ParentActivityId` / `ActivityName`. New `FATAL` Level.
- **Redaction (ADR-023).** Always-on for `[SecureString]`, `[PSCredential]`,
  and metadata keys matching `(?i)password|secret|token|apikey`.
  Configurable via `Set-DJMLogConfig -RedactionPatterns` (regex array) and
  `-RedactionPresets ('Email', 'BearerToken', 'CreditCard')`.
- **Sampling (ADR-024).** Per-level rates via
  `Set-DJMLogConfig -SampleRate @{ DEBUG = 0.01; INFO = 0.1 }`. Applied
  after MinLevel filtering, before the channel write — sampled-out entries
  cost only the level lookup.
- **Read-DJMLog `-Stream`.** Per-entry pipeline emission via
  `[System.IO.File]::ReadLines`; constant memory regardless of file size.
- **Log Analytics gzip (ADR-025).** Each batch gzip-compressed
  (`CompressionLevel.Fastest`) with `Content-Encoding: gzip`. 950 KB
  pre-compression target preserved; falls back to uncompressed body on
  gzip failure with SelfLog entry.
- **New public cmdlets**: `Flush-DJMLog`, `Wait-DJMLog`, `Start-DJMActivity`,
  `Stop-DJMActivity`.
- **Get-DJMLogDiagnostics extended**: now includes `EnqueuedCount`,
  `ProcessedCount`, `DroppedCount`, `QueuedCount`. Errors merge from main +
  writer queues.

### Changed

- **Write-DJMLog is asynchronous.** Returns after enqueueing; the file
  write happens on the writer runspace. Scripts that need synchronous
  on-disk durability must call `Flush-DJMLog` before reading the file. The
  test runner and tools that need v1.x synchronous semantics can opt-in
  via `$env:DJMLOG_SYNC_WRITES = '1'`.
- **Send-DJMLogBuffer becomes a back-compat wrapper** over `Flush-DJMLog`.
  The pre-v2 LA flush logic moved into the writer's
  `Invoke-LogAnalyticsFlush`.
- Coverage threshold remains 70 % but `Start-DJMWriter.ps1` is excluded
  from the coverage path because the writer-loop scriptblock body runs in
  a different runspace and Pester profiler-based coverage cannot count
  execution there. Resulting coverage: 81.7 %.

### Fixed

- **BUG-018**: Stop-DJMWriter deadlock on `Channel.TryComplete` —
  resolved by passing a `CancellationToken` to `WaitToReadAsync` so the
  writer can be interrupted from the main runspace.
- **BUG-019**: `GetNewClosure()` rebinds scriptblocks out of module
  session state; `Read-DJMLog` and `Invoke-DJMRedaction` refactored to
  inline parse loops / top-level private functions.
- **BUG-020**: `Channel<hashtable>` rejected `Dictionary<string, PSObject>`
  entries silently; switched to `Channel<object>` and rely on `IDictionary`
  semantics in dispatch.
- **BUG-021**: `Interlocked.Increment([ref]$h.Property)` on a hashtable
  property had no effect (PowerShell wraps the value, not the storage);
  replaced with `Monitor.Enter` blocks on `SyncRoot`.
- **BUG-022**: PowerShell didn't resolve the parameterless
  `WaitToReadAsync()` overload; pass `CancellationToken` explicitly.

### Migration notes

```powershell
# Before (v1.x synchronous Write-DJMLog):
Write-DJMLog -Message 'x'
$content = Get-Content ./log.jsonl   # worked

# After (v2.0 async by default):
Write-DJMLog -Message 'x'
$null = Flush-DJMLog -TimeoutSec 5    # required before reading
$content = Get-Content ./log.jsonl
```

Certificate-auth Log Analytics flush still flows through the main-runspace
`Send-DJMLogBuffer -Force` path; the writer-runspace flush handles
`AppSecret` + `BearerTokenExternal` only. Full cert support inside the
writer is a v2.x follow-up.

## [1.2.0] - 2026-04-26

Robustness + CI hardening. No log-entry schema change.

### Added

- **HTTP retry helper (ADR-016).** New
  `Private/Invoke-DJMRestMethodWithRetry` honours `Retry-After` on 429,
  applies exponential backoff with jitter on 5xx, and forwards a per-call
  `-TimeoutSec`. Both `Get-DJMBearerToken` and `Send-DJMLogBuffer` route
  through it.
- **Half-open circuit breaker (ADR-017).** After
  `HalfOpenAfterSeconds` (default 300) the next non-`-Force`
  `Send-DJMLogBuffer` call attempts a single-shot probe with
  `MaxRetries = 1`; success closes, failure refreshes the timer.
  `Get-DJMLogDiagnostics.CircuitBreakerState` exposes
  `Closed` / `Open` / `HalfOpen-Probe-Pending`.
- **MaxBufferBytes** parameter on `Set-DJMLogConfig` (default 50 MB).
  Drop-head FIFO eviction when count or byte cap is exceeded; running
  total maintained incrementally.
- **`Send-DJMLogBuffer` chunking rewrite.** Raised target to 950 KB
  (raw, pre-compression) using incremental UTF-8 byte accounting. Records
  exceeding 950 KB on their own are rejected (dropped from the buffer +
  SelfLog entry queued).
- **CI supply-chain hygiene (ADR-018).** Every `uses:` in workflow files
  pinned to full commit SHA with a trailing `# vN` comment; Dependabot
  tracks `github-actions` weekly. Test job runs on a `pwsh: ['7.4', '7.5']`
  matrix in `mcr.microsoft.com/powershell:<ver>-ubuntu-22.04` containers.
  New `dependency-audit` and `integration` CI jobs.

### Changed

- **`ConvertTo-DJMDictionary` `-OnDuplicateKey`** new parameter
  (`Overwrite` / `Error` / `KeepFirst`); default `Overwrite`.
- **`Set-DJMLogConfig` validation.** Emits a single consolidated error
  listing every missing field when `LogAnalyticsEnabled = $true`.
  Warns when `DcrEndpointUri` host doesn't match `CloudEnvironment`.
- **Cert selection unified** across thumbprint and subject paths
  (`NotAfter > UtcNow`, `HasPrivateKey`, key size ≥ 2048; latest expiry
  wins).
- **Module dot-source isolation.** `DJMLog.psm1` wraps each
  `.` source in try/catch; failures queue to SelfLog; only throws if a
  `FunctionsToExport` entry can't be resolved.
- **Pester coverage threshold** raised from 50 % to 70 %.
- `PSAvoidUsingCmdletAliases`, `PSUseApprovedVerbs`, and
  `PSAvoidGlobalVars` promoted to `Severity = 'Error'`.
- **`Get-DJMLogDiagnostics` return shape** (breaking) — now
  `[pscustomobject]` with `Errors`, `CircuitBreakerState`,
  `AutoFlushOpenedAtUtc`, instead of a flat error array.

### Fixed

- **BUG-014**: First-attempt 429 / 5xx tripped the auto-flush circuit
  breaker — see ADR-016.
- **BUG-015**: Open circuit breaker had no auto-recovery path — see
  ADR-017.
- **BUG-016**: 500 KB chunk threshold under-utilised batches and didn't
  reject single records > 950 KB pre-compression.
- **BUG-017**: `MaxBufferBytes` byte-cap recompute was O(N²) on every
  `Write-DJMLog`; replaced with `$script:BufferByteTotal` scalar
  maintained incrementally.

## [1.1.0] - 2026-04-26

Safety release. No API change; `Get-DJMLogDiagnostics` is the only new
public cmdlet.

### Added

- **`Get-DJMLogDiagnostics` (ADR-013).** Surface for the bounded SelfLog
  queue. Returns the last 100 internal-error records (`UtcTimestamp`,
  `Source`, `Message`, `Exception`). Used to detect silent log-write
  drops, mutex timeouts, rotation failures, and Log Analytics flush
  errors.
- **`Write-DJMFallback` private helper.** Last-resort sink writes to the
  Windows Application Event Log first (source `DJMLog`, registered
  lazily) and falls back to `[Console]::Error` on non-Windows or
  registration failure.
- `Metadata.Error.ExceptionChain` array — captures the full
  `InnerException` chain (BFS, cycle-protected) so multi-task
  `AggregateException` errors don't lose information.
- `[OutputType()]` declarations on every public function.

### Changed

- **AppSecret always stored as SecureString (ADR-015).**
  `Set-DJMLogConfig` converts string input to `[SecureString]` on
  assignment. `Get-DJMBearerToken` materialises plaintext into a
  `[char[]]` buffer + zeroes the buffer in `finally`. Plain-string input
  path is deprecated.

### Fixed

- **BUG-009**: Concurrent rotation race in `Write-DJMLog`. Rotation
  decision and `[System.IO.File]::Move` moved inside the named-mutex
  block. Losing runspaces re-stat the (now small) file via
  `FileInfo.Refresh()` and skip rotation cleanly.
- **BUG-010**: Retention loop aborted on a single locked file.
  `[System.IO.Directory]::GetFiles()` results are `@()`-cast; per-file
  `try/catch` with SelfLog enqueue. `[System.IO.FileInfo]` replaces
  `GetCreationTimeUtc` (returns sentinel on access-denied instead of
  throwing). `RetainFiles` slice guarded with explicit `$deleteCount > 0`.
- **BUG-011**: `Expand-MetadataValue` infinite recursion on cyclic
  objects. Added a `HashSet[object]` keyed by
  `[ReferenceEqualityComparer]::Instance` passed through recursion;
  re-entry emits the literal string `'<cycle>'`.
- **BUG-012**: `Send-DJMLogBuffer` index-based `RemoveRange` could remove
  the wrong entries when a concurrent `Write-DJMLog` evicted the head
  during the HTTP POST. New `Remove-DJMSentEntries` private helper
  removes sent entries by reference.
- **BUG-013**: `AppSecret` stored as plaintext string in module scope.
- **BUG-001 (ADR-014)**: `$script:LogBuffer` was not thread-safe under
  `ForEach-Object -Parallel`. Added `$script:BufferLock` (`SemaphoreSlim`)
  guarding all buffer mutations as the v1.1 interim fix; superseded by
  the v2.0 async writer.

## [1.0.1] - 2026-03-30

### Added

- Tag-driven release pipeline (`release.yml`): OIDC auth via
  `azure/login@v2`, `Invoke-Build Release` publishes to ACR via
  `Publish-PSResource`, GitHub Release with auto-generated notes.
- `deploy` GitHub environment with `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`,
  `AZURE_SUBSCRIPTION_ID` secrets and `ACR_LOGIN_SERVER` variable
  (ADR-011).
- `sync-dev.yml` workflow: auto-merges `main` into `dev` after each push
  to `main` (ADR-009).
- `Invoke-Build` adopted as build orchestrator (`DJMLog.build.ps1` +
  `build.config.psd1`); standard tasks `Clean / Lint / Test / Docs /
  AssertDocsClean / BumpVersion / Pack / Build` (ADR-010).
- Pre-push hook installer (`scripts/Install-GitHooks.ps1`).

### Changed

- Docs pipeline migrated from MkDocs Material to Zensical v0.0.27
  (ADR-008).

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
