# Manual Testing Plan — DJMLog v2.0.0

> Hands-on validation of the published v2.0.0 artifact against real Azure infrastructure.
> Automated coverage is comprehensive (335 tests, 86.5%), but no human has actually used the module end-to-end.
> Pick up here when ready.

## Goals

1. Validate the **published ACR artifact** (not the local repo) — proves the release pipeline output is consumable
2. Exercise auth methods that have only been mocked: cert JWT against a real DCR, managed identity via real IMDS
3. Surface ergonomic issues only humans notice: surprising defaults, missing helpers, painful call sites
4. Provide the trigger condition for ADR-031 (flip the Logs Ingestion CI gate from advisory to required)

---

## Phase A — Local sinks only (no Azure required, ~30 min)

Cheap smoke test. Catches the obvious "does it even import" issues before you spend Azure time.

### A.1 Install from ACR (fresh pwsh)
- [ ] Open a clean `pwsh -NoProfile` session on a machine that has never imported DJMLog
- [ ] `Connect-AzAccount` (any tenant — only needs ACR read)
- [ ] `Register-PSResourceRepository -Name HomeACR -Uri 'https://<acr-name>.azurecr.io' -Trusted` (if not already)
- [ ] `Install-PSResource DJMLog -Repository HomeACR`
- [ ] `Import-Module DJMLog ; Get-Command -Module DJMLog` — confirm 11 public functions

### A.2 File sink basics
- [ ] `Set-DJMLogConfig -Path "$env:TEMP\djmlog-manual\test.jsonl" -MinLevel DEBUG -Sinks File`
- [ ] `Write-DJMLog -Level INFO -Message 'hello' -Metadata @{ user = 'doug' }`
- [ ] `Flush-DJMLog ; Wait-DJMLog -TimeoutSec 5`
- [ ] Open the .jsonl in an editor — verify schema v2 fields (SchemaVersion, SeverityNumber, Host.{MachineName,ProcessId,UserName,PSVersion}, Caller)
- [ ] `Read-DJMLog -Path "$env:TEMP\djmlog-manual\test.jsonl"` — verify normalized columns
- [ ] `Read-DJMLog -Path "$env:TEMP\djmlog-manual\test.jsonl" -Stream` — verify per-entry pipeline emission

### A.3 Activities + correlation
- [ ] `Start-DJMActivity -Name 'OuterOp'` — capture the returned correlation ID
- [ ] `Write-DJMLog INFO 'inside outer'`
- [ ] `Start-DJMActivity -Name 'InnerOp'` (nested)
- [ ] `Write-DJMLog INFO 'inside inner'`
- [ ] `Stop-DJMActivity` (closes inner — verify duration entry)
- [ ] `Stop-DJMActivity` (closes outer)
- [ ] `Flush-DJMLog`
- [ ] In the file: confirm `ActivityId` propagates, `ParentActivityId` is set on the inner, `ActivityName` matches, and the duration entries fired

### A.4 Rotation under sustained writes
- [ ] `Set-DJMLogConfig -Path ... -MaxSizeMB 0.01 -RetainFiles 3` (force rotation fast)
- [ ] Write 200 entries in a loop
- [ ] `Flush-DJMLog`
- [ ] Verify rotated files exist with timestamp suffixes; verify retention deleted older ones; verify exactly one currently-active file

### A.5 Redaction
- [ ] `Set-DJMLogConfig -Path ... -RedactionPresets @('Email','BearerToken','CreditCard')`
- [ ] `Write-DJMLog INFO 'card=4111111111111111 email=foo@example.com bearer=eyJ...'`
- [ ] Verify the file contains `<redacted>` placeholders, not the originals
- [ ] Pass a `[PSCredential]` in `-Metadata` — verify the password value is redacted

### A.6 Console + EventLog sinks
- [ ] `Set-DJMLogConfig -Sinks @('File','Console')` — verify colorized stdout
- [ ] (Windows-only) `Set-DJMLogConfig -Sinks @('File','EventLog')` — admin pwsh required for source registration; verify entries appear in Event Viewer under the configured log

### A.7 Diagnostics & breaker
- [ ] `Get-DJMLogDiagnostics` — verify EnqueuedCount/ProcessedCount/DroppedCount/QueuedCount, CircuitBreakerState = 'Closed', empty Errors

### A.8 Subprocess hang regression (BUG-023)
- [ ] `pwsh -NoProfile -Command "Import-Module DJMLog; Set-DJMLogConfig -Path '$env:TEMP\hang.jsonl'; Write-DJMLog INFO 'test'; Wait-DJMLog -TimeoutSec 5"`
- [ ] Verify the process exits within ~30s (NOT 19 min). If it hangs, wrap via `scripts/Invoke-WithDJMHostExit.ps1` per ADR-030.

**Phase A exit criteria:** all eight sections green. If any fail, log a bug in `../bugs.md` and fix before Phase B.

---

## Phase B — Azure Log Analytics round-trip (cert auth, ~1-2 hr provisioning)

This is the test that actually validates the LA sink. It also produces the infrastructure ADR-031 needs.

### B.1 Provision (one-time, ~1 hr)
- [ ] In target tenant (GCCHigh preferred since that's the default cloud), create:
  - Log Analytics workspace (or reuse existing)
  - Custom table `DJMLogManual_CL` with columns: TimeGenerated (datetime), Level (string), Message (string), CorrelationId (string), Metadata (dynamic)
  - Data Collection Endpoint (DCE) in the same region
  - Data Collection Rule (DCR) targeting the table — record DCR immutable ID + stream name (`Custom-DJMLogManual_CL` typically)
  - Entra app registration `DJMLog-ManualTest` with a self-signed cert in CurrentUser\My (or LocalMachine\My)
  - Assign the app `Monitoring Metrics Publisher` on the DCR

Document IDs/URIs in a local `manual-test-config.json` (gitignored — contains tenant/app/DCR identifiers). Sample shape:
```json
{
    "Path": "C:\\Temp\\djmlog-manual\\la-test.jsonl",
    "Sinks": ["File", "LogAnalytics"],
    "LogAnalyticsEnabled": true,
    "CloudEnvironment": "GCCHigh",
    "DcrEndpointUri": "<dce-endpoint-uri>",
    "DcrImmutableId": "<dcr-immutable-id>",
    "DcrStreamName": "Custom-DJMLogManual_CL",
    "TenantId": "<tenant-id>",
    "AppId": "<app-id>",
    "CertificateSubject": "CN=DJMLog-ManualTest",
    "FlushThreshold": 10
}
```

### B.2 Cert-auth round-trip
- [ ] `Set-DJMLogConfig -ConfigPath ./manual-test-config.json`
- [ ] `Write-DJMLog INFO 'manual test 1' -Metadata @{ run = (Get-Date -Format o) }`
- [ ] Repeat 15 times to exceed FlushThreshold
- [ ] `Wait-DJMLog -TimeoutSec 30`
- [ ] In the LA workspace: `DJMLogManual_CL | where TimeGenerated > ago(5m)` — confirm entries arrive, fields populated correctly
- [ ] `Get-DJMLogDiagnostics` — confirm CircuitBreakerState = 'Closed', no errors

### B.3 Force-flush + back-compat
- [ ] Write a few more entries
- [ ] `Send-DJMLogBuffer -Force` (legacy v1.x path) — verify it still works (forwards to Flush-DJMLog per v2.0 wrapper)
- [ ] Confirm entries arrive in LA

### B.4 Circuit breaker behavior (ADR-017)
- [ ] Block outbound to the DCE host (firewall rule or yank Wi-Fi mid-flush)
- [ ] Write enough entries to trigger MaxFlushRetries failures
- [ ] `Get-DJMLogDiagnostics` — confirm CircuitBreakerState = 'Open' and AutoFlushOpenedAtUtc is set
- [ ] Restore network
- [ ] Wait 5 min (HalfOpenAfterSeconds default = 300)
- [ ] Trigger another write/flush — confirm the probe runs and breaker returns to 'Closed'

### B.5 Oversized record drop (BUG-016)
- [ ] `Write-DJMLog INFO 'oversize' -Metadata @{ payload = ('x' * 1000000) }` (1 MB string)
- [ ] Confirm the record is dropped (not sent), removed from buffer, and surfaced in `(Get-DJMLogDiagnostics).Errors`

**Phase B exit criteria:** B.2 + B.4 green. B.3, B.5 are nice-to-have but reveal real-world behavior.

---

## Phase C — Managed Identity (Azure VM, ~30 min)

Validates ADR-029's IMDS path against real metadata. Only meaningful on an actual Azure VM.

- [ ] Provision a small Azure VM (B2s is fine) in the target cloud, system-assigned MI enabled
- [ ] Assign the VM's MI `Monitoring Metrics Publisher` on the DCR from B.1
- [ ] Install pwsh 7.5+, install DJMLog from ACR
- [ ] `Set-DJMLogConfig -UseManagedIdentity ... ` (drop the cert/AppId/TenantId fields entirely)
- [ ] Write a few entries; `Wait-DJMLog`
- [ ] Confirm entries arrive in LA
- [ ] (Optional) Repeat with a user-assigned MI via `-ManagedIdentityClientId`

---

## Phase D — UidSyncEngine integration (the real proving ground)

Wire DJMLog into UidSyncEngine. This is the ADR-031 trigger condition — once UidSyncEngine ships LA sink usage, the CI gate enablement checklist (preserved in `../issues.md` "Deferred follow-up: Logs Ingestion CI gate enablement") becomes worth executing.

- [ ] Add DJMLog as a UidSyncEngine module dependency (Install-PSResource at module-load time, or RequiredModules in manifest)
- [ ] Replace the existing logging calls in UidSyncEngine with `Write-DJMLog` + `Start-/Stop-DJMActivity`
- [ ] Run a real sync cycle in a non-prod tenant
- [ ] Verify entries land in the configured sink(s)
- [ ] Note any DX rough edges (missing helpers, surprising defaults, painful call sites) — file as v2.x enhancement candidates in `../issues.md`

---

## After completion

- [ ] Append a "Manual testing complete" entry to `../issues.md` summarizing what passed, any bugs found, and DX feedback
- [ ] If bugs found, add to `../bugs.md` with the standard format
- [ ] If Phase D shipped, flip ADR-031's trigger and execute the "Deferred follow-up: Logs Ingestion CI gate enablement" checklist in `../issues.md`
- [ ] Delete this file (or move to `40-Archive/` in the vault) once retired

## References
- ADR-029 (managed identity via IMDS)
- ADR-027 (cert auth in writer runspace)
- ADR-025 (gzip + 950 KB chunking)
- ADR-017 (half-open circuit breaker)
- ADR-031 (Logs Ingestion CI gate deferral — this plan's Phase D is the trigger)
- BUG-023 (subprocess hang — Phase A.8 regression check)
- `../issues.md` — "Deferred follow-up: Logs Ingestion CI gate enablement"
