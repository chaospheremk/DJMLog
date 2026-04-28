---
document type: cmdlet
external help file: DJMLog-Help.xml
HelpUri: ''
Locale: en-US
Module Name: DJMLog
ms.date: 01/01/1970
PlatyPS schema version: 2024-05-01
title: Stop-DJMActivity
---

# Stop-DJMActivity

## SYNOPSIS

Pops the most recently pushed activity scope and emits a duration entry.

## SYNTAX

### __AllParameterSets

```
Stop-DJMActivity [<CommonParameters>]
```

## ALIASES

None.
## DESCRIPTION

Pops the top of the per-runspace activity stack and writes an INFO entry of
the form "Activity '<Name>' finished" with Metadata.Activity.DurationMs.

Calling Stop-DJMActivity when the stack is empty emits a non-terminating
warning and is otherwise a no-op.

## EXAMPLES

### EXAMPLE 1

Start-DJMActivity -Name 'WorkUnit'
try { ... } finally { Stop-DJMActivity }

## PARAMETERS

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### [pscustomobject] - the popped frame



### System.Management.Automation.PSObject



## NOTES

## RELATED LINKS



