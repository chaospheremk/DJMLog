---
document type: cmdlet
external help file: DJMLog-Help.xml
HelpUri: ''
Locale: en-US
Module Name: DJMLog
ms.date: 01/01/1970
PlatyPS schema version: 2024-05-01
title: Start-DJMActivity
---

# Start-DJMActivity

## SYNOPSIS

Pushes a new activity scope onto the per-runspace activity stack.

## SYNTAX

### __AllParameterSets

```
Start-DJMActivity [-Name] <string> [[-CorrelationId] <string>]
```

## ALIASES

None.
## DESCRIPTION

Activities give Write-DJMLog a default CorrelationId, ParentActivityId, and
ActivityName when those parameters are omitted.
Activities nest: the new
activity's ParentActivityId is the previous top-of-stack activity (if any).

Stop-DJMActivity pops the most recently pushed activity and emits an
INFO-level "activity finished" entry containing the elapsed duration.

The activity stack is per-runspace ($script: scope).
Nesting is tracked
locally; entries pushed on the writer's channel carry the activity context
snapshotted at write time.

Activities also feed into the W3C Trace Context pickup: when
[System.Diagnostics.Activity]::Current is non-null at write time,
Write-DJMLog records its TraceId and SpanId under Metadata.Trace.

## EXAMPLES

### EXAMPLE 1

# Wrap a unit of work in an activity
Start-DJMActivity -Name 'SyncTenantUsers'
try {
    Write-DJMLog -Message 'Sync started'
    # ... work ...
    Write-DJMLog -Message 'Sync completed'
}
finally {
    Stop-DJMActivity
}

## PARAMETERS

### -CorrelationId

Override the activity's correlation id.
Defaults to a new GUID.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 1
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Name

Required.
Human-readable activity name (e.g.
'ProvisionUser').

```yaml
Type: System.String
DefaultValue: ''
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

### [pscustomobject] - the activity frame { Id



### System.Management.Automation.PSObject



## NOTES

## RELATED LINKS



