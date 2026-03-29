---
document type: cmdlet
external help file: DJMLog-Help.xml
HelpUri: ''
Locale: en-US
Module Name: DJMLog
ms.date: 03/28/2026
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
in chunked batches of up to 500 KB each.
Each record's UtcTimestamp is mapped to
the TimeGenerated field so timestamps remain accurate regardless of when the batch
is sent.

Preconditions:
  - LogAnalyticsEnabled must be $true (via Set-DJMLogConfig)
  - DcrEndpointUri, DcrImmutableId, and DcrStreamName must be configured
  - The buffer must contain at least one entry
  - Auto-flush must not be disabled (circuit breaker) unless -Force is used

On success, sent entries are removed from the buffer, the failure count is reset,
and auto-flush is re-enabled.
On failure, the failure count is incremented and
auto-flush is disabled when MaxFlushRetries is reached.
The function breaks on the
first batch failure so partially sent entries are removed while unsent entries
remain buffered for the next attempt.

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

## NOTES

## RELATED LINKS



