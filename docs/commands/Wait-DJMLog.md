---
document type: cmdlet
external help file: DJMLog-Help.xml
HelpUri: ''
Locale: en-US
Module Name: DJMLog
ms.date: 01/01/1970
PlatyPS schema version: 2024-05-01
title: Wait-DJMLog
---

# Wait-DJMLog

## SYNOPSIS

Blocks until the async writer channel has drained, with a timeout.

## SYNTAX

### __AllParameterSets

```
Wait-DJMLog [-TimeoutSec] <int>
```

## ALIASES

None.
## DESCRIPTION

Wait-DJMLog is identical to Flush-DJMLog with a mandatory positive timeout
and no Log Analytics flush sentinel.
Use it when you need to wait for
pending writes to land on disk without forcing a Log Analytics POST.

## EXAMPLES

### EXAMPLE 1

# Wait up to 5 seconds for queued entries to land
if (-not (Wait-DJMLog -TimeoutSec 5)) {
    Write-Warning 'Writer did not drain within 5s'
}

## PARAMETERS

### -TimeoutSec

Maximum number of seconds to wait.
Mandatory and must be > 0.

```yaml
Type: System.Int32
DefaultValue: 0
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: true
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

## RELATED LINKS



