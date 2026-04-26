---
document type: cmdlet
external help file: DJMLog-Help.xml
HelpUri: ''
Locale: en-US
Module Name: DJMLog
ms.date: 01/01/1970
PlatyPS schema version: 2024-05-01
title: Flush-DJMLog
---

# Flush-DJMLog

## SYNOPSIS

Drains the async writer channel and (if Log Analytics is enabled) flushes the in-memory buffer.

## SYNTAX

### __AllParameterSets

```
Flush-DJMLog [[-TimeoutSec] <int>] [-Force] [<CommonParameters>]
```

## ALIASES

None.
## DESCRIPTION

Blocks until every entry submitted before the call has been processed by the
writer runspace.
When Log Analytics is enabled, additionally signals the
writer to flush its in-memory buffer to the configured DCR endpoint
immediately (subject to circuit-breaker state).

Use Flush-DJMLog before terminating an automation script so in-flight log
entries reach disk and the configured remote sinks before the process exits.

## EXAMPLES

### EXAMPLE 1

# End-of-script drain
try { ... } finally { [void](Flush-DJMLog) }

### EXAMPLE 2

# Force a Log Analytics flush after a known outage recovered
Flush-DJMLog -Force

## PARAMETERS

### -Force

When Log Analytics auto-flush is in the Open circuit-breaker state, -Force
issues an explicit flush attempt regardless.
The half-open transition is
bypassed.

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

### -TimeoutSec

Maximum number of seconds to wait for the channel drain.
Defaults to -1
(wait indefinitely).
Returns $true on success, $false on timeout.

```yaml
Type: System.Int32
DefaultValue: -1
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
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

### [bool] $true if drained within the timeout



### System.Boolean



## NOTES

The verb 'Flush' is the de-facto standard term for draining a logging
buffer (Serilog Flush, NLog Flush, Microsoft.Extensions.Logging Flush).
PowerShell does not include it in the approved-verbs list; the cmdlet
suppresses PSUseApprovedVerbs at the call site rather than rename to a
less-discoverable approved verb such as Sync- or Submit-.


## RELATED LINKS



