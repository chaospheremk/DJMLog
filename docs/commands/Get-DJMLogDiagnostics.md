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

Returns the module's internal error queue (SelfLog).

## SYNTAX

### __AllParameterSets

```
Get-DJMLogDiagnostics [<CommonParameters>]
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

Get-DJMLogDiagnostics returns a snapshot of that queue so callers can
surface logging-pipeline failures (mutex timeouts, rotation errors,
Log Analytics flush failures, token acquisition errors) at their own
discretion.
Newest entries are last.

The queue is in-memory only and cleared on module reload.

## EXAMPLES

### EXAMPLE 1

# Inspect recent internal failures
Get-DJMLogDiagnostics | Format-Table UtcTimestamp, Source, Message

### EXAMPLE 2

# Filter to flush failures only
Get-DJMLogDiagnostics | Where-Object Source -eq 'Send-DJMLogBuffer'

## PARAMETERS

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### [pscustomobject[]] Each entry has fields:
    UtcTimestamp - ISO 8601 timestamp of the internal error
    Source       - Originating function (e.g. 'Write-DJMLog')
    Message      - Human-readable failure description
    Exception    - The original exception object



### System.Management.Automation.PSObject



## NOTES

## RELATED LINKS



