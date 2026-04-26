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

Back-compat wrapper. Forwards to Flush-DJMLog (v2.0 async writer ADR-019).

## SYNTAX

### __AllParameterSets

```
Send-DJMLogBuffer [-Force] [<CommonParameters>]
```

## ALIASES

None.
## DESCRIPTION

In v1.x, Send-DJMLogBuffer flushed the in-memory Log Analytics buffer to
the configured DCR endpoint synchronously from the calling runspace.

In v2.0, the Log Analytics buffer lives inside the dedicated writer
runspace.
Flush behaviour is delegated to Flush-DJMLog, which signals the
writer to perform a flush via a sentinel entry on the channel and then
blocks until the channel has drained.

The -Force semantics map directly to Flush-DJMLog -Force.

Migration guidance:
    - Existing scripts that called `Send-DJMLogBuffer` continue to work.
    - New scripts should use `Flush-DJMLog` directly to express intent.

## EXAMPLES

### EXAMPLE 1

Send-DJMLogBuffer            # equivalent to Flush-DJMLog
Send-DJMLogBuffer -Force     # equivalent to Flush-DJMLog -Force

## PARAMETERS

### -Force

Forwarded to Flush-DJMLog -Force.
Bypasses the half-open transition.

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

Returns nothing for v1.x source compatibility (Flush-DJMLog returns [bool]).


## RELATED LINKS



