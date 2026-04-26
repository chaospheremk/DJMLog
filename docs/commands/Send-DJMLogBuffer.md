---
document type: cmdlet
external help file: DJMLog-Help.xml
HelpUri: ''
Locale: en-US
Module Name: DJMLog
ms.date: 01/01/1970
PlatyPS schema version: 2024-05-01
title: Send-DJMLogBuffer
---

# Send-DJMLogBuffer

## SYNOPSIS

Flushes the in-memory log buffer to Azure Log Analytics via the Logs Ingestion API.

## SYNTAX

### __AllParameterSets

```
Send-DJMLogBuffer [-Force] [<CommonParameters>]
```

## ALIASES

None.
## DESCRIPTION

Sends buffered log entries to the configured Data Collection Rule (DCR) endpoint
in chunked batches of up to 950 KB each (raw, pre-compression).
Each record's
UtcTimestamp is mapped to the TimeGenerated field so timestamps remain accurate
regardless of when the batch is sent.

Chunking uses incremental UTF-8 byte accounting: each record's encoded length is
summed against a running batch size, and a new batch is started before the
cumulative size would cross the 950 KB threshold.
Records whose individual
serialised size already exceeds 950 KB are rejected — they are removed from the
buffer and a SelfLog entry is queued so callers can detect the drop via
Get-DJMLogDiagnostics.

Preconditions:
  - LogAnalyticsEnabled must be $true (via Set-DJMLogConfig)
  - DcrEndpointUri, DcrImmutableId, and DcrStreamName must be configured
  - The buffer must contain at least one entry
  - Auto-flush must not be disabled (circuit breaker) unless -Force is used,
    or the half-open window (HalfOpenAfterSeconds, default 300s) has elapsed

Circuit breaker (per ADR-017):
  Closed   - normal operation.
Failures up to MaxFlushRetries trip the breaker.
  Open     - auto-flush rejected; the call returns with a warning.
-Force
             overrides.
  HalfOpen - once HalfOpenAfterSeconds has elapsed since the breaker opened,
             the next non-Force call attempts a single-shot probe (MaxRetries=1).
             Success closes the breaker; failure refreshes the open timer.

HTTP requests (token acquisition + DCR POST) route through the
Invoke-DJMRestMethodWithRetry helper, which honours Retry-After on 429 and
applies exponential backoff with jitter on 5xx (per ADR-016).

Buffer access is serialised through an in-process SemaphoreSlim
($script:BufferLock) so concurrent Write-DJMLog and Send-DJMLogBuffer calls
in the same process cannot corrupt the underlying List.
Cross-process file
writes are still serialised by the named OS mutex.

## EXAMPLES

### EXAMPLE 1

# Manually flush the buffer
Send-DJMLogBuffer

### EXAMPLE 2

# Force flush after circuit breaker tripped
Send-DJMLogBuffer -Force

## PARAMETERS

### -Force

Bypasses the auto-flush circuit breaker.
Use after investigating and resolving
the underlying connectivity or configuration issue.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### System.Void



## NOTES

## RELATED LINKS



