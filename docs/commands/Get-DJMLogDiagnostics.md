---
document type: cmdlet
external help file: DJMLog-Help.xml
HelpUri: ''
Locale: en-US
Module Name: DJMLog
ms.date: 01/01/1970
PlatyPS schema version: 2024-05-01
title: Get-DJMLogDiagnostics
---

# Get-DJMLogDiagnostics

## SYNOPSIS

Returns the module's internal error queue (SelfLog) plus circuit breaker state.

## SYNTAX

### __AllParameterSets

```
Get-DJMLogDiagnostics
```

## ALIASES

None.
## DESCRIPTION

DJMLog deliberately avoids throwing terminating errors during log writes —
a logging library that crashes its host is unacceptable.
Instead, every
catch block in Write-DJMLog, Send-DJMLogBuffer, Read-DJMLog, and
Get-DJMBearerToken records the failure into a bounded in-memory queue
(last 100 entries, FIFO eviction).

Get-DJMLogDiagnostics returns a snapshot of that queue together with the
Log Analytics circuit breaker state so callers can surface logging-pipeline
failures (mutex timeouts, rotation errors, Log Analytics flush failures,
token acquisition errors) at their own discretion.
Newest entries are last.

The queue is in-memory only and cleared on module reload.

## EXAMPLES

### EXAMPLE 1

# Inspect recent internal failures
$diag = Get-DJMLogDiagnostics
$diag.Errors | Format-Table UtcTimestamp, Source, Message

### EXAMPLE 2

# Check circuit breaker state in long-running automation
if ((Get-DJMLogDiagnostics).CircuitBreakerState -ne 'Closed') {
    # alert / page
}

## PARAMETERS

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### [pscustomobject] with fields:
    Errors               - Array of internal error entries
                           (UtcTimestamp



### System.Management.Automation.PSObject



## NOTES

Breaking change in v1.2: this cmdlet now returns a single PSCustomObject
instead of an array of error records.
v1.1 callers must migrate from
`Get-DJMLogDiagnostics | ...` to `(Get-DJMLogDiagnostics).Errors | ...`.


## RELATED LINKS



