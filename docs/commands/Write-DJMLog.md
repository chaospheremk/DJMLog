---
document type: cmdlet
external help file: DJMLog-Help.xml
HelpUri: ''
Locale: en-US
Module Name: DJMLog
ms.date: 01/01/1970
PlatyPS schema version: 2024-05-01
title: Write-DJMLog
---

# Write-DJMLog

## SYNOPSIS

Submits a structured entry to the async writer for fan-out across the configured sinks.

## SYNTAX

### Error

```
Write-DJMLog -Message <string> -ErrorObject <ErrorRecord> [-Level <string>]
 [-CorrelationId <string>] [-LogPath <string>] [-Metadata <psobject>] [-MinLevel <string>]
 [-MaxSizeMB <double>] [-RotationSchedule <string>] [-RetainDays <int>] [-RetainFiles <int>]
 [-MutexTimeoutMs <int>] [-Depth <int>] [-CallerDepth <int>] [-NoCaller] [-NoHostContext]
 [-PassThru] [<CommonParameters>]
```

### Default

```
Write-DJMLog -Message <string> [-Level <string>] [-CorrelationId <string>] [-LogPath <string>]
 [-Metadata <psobject>] [-MinLevel <string>] [-MaxSizeMB <double>] [-RotationSchedule <string>]
 [-RetainDays <int>] [-RetainFiles <int>] [-MutexTimeoutMs <int>] [-Depth <int>]
 [-CallerDepth <int>] [-NoCaller] [-NoHostContext] [-PassThru] [<CommonParameters>]
```

## ALIASES

None.
## DESCRIPTION

v2.0 Write-DJMLog is the *producer* side of the async writer: it validates,
enriches (host context, activity stack, W3C Trace Context), redacts, and
pushes the entry onto a bounded channel.
A dedicated writer runspace drains
the channel and feeds each enabled sink (File / Console / EventLog /
LogAnalytics).

The Channel is BoundedChannel<hashtable> with FullMode = DropOldest.
Drops
are surfaced via Get-DJMLogDiagnostics.DroppedCount.
Use Flush-DJMLog or
Wait-DJMLog before script exit to drain pending entries.

Schema v2 (per ADR-022):
    SchemaVersion       - "2"
    UtcTimestamp        - ISO 8601 UTC
    Level               - INFO | WARN | ERROR | DEBUG | FATAL
    SeverityNumber      - OTel SeverityNumber (1..24)
    Message
    CorrelationId
    ActivityId          - top-of-stack activity id (when in an activity scope)
    ParentActivityId    - parent in the activity stack
    ActivityName        - top-of-stack activity name
    Host                - { MachineName, ProcessId, UserName, PSVersion }
                          when -IncludeHostContext is on (default)
    Metadata            - free-form.
Metadata.Trace { TraceId, SpanId } is
                          auto-populated when [Activity]::Current is non-null.
                          Metadata.Caller, Metadata.Error are populated as in v1.

Min-level filtering and sampling apply BEFORE the channel write so suppressed
entries don't consume channel capacity.

Redaction:
    SecureString and PSCredential metadata values are unconditionally
    replaced with '[REDACTED]'.
Keys matching (?i)password|secret|token|apikey
    are redacted.
Configurable -RedactionPatterns / -RedactionPresets on
    Set-DJMLogConfig add string-level regex redaction.

Activity scopes:
    When an activity is on the stack (Start-DJMActivity), its CorrelationId
    is used unless -CorrelationId was supplied explicitly.

Breaking changes from v1:
    - Returns immediately after enqueue; the file write is asynchronous.
      For scripts that previously assumed synchronous on-disk durability,
      call Flush-DJMLog before relying on the file content.
    - Schema gains SchemaVersion / SeverityNumber / Host / ActivityId /
      ParentActivityId / ActivityName fields.
Read-DJMLog auto-detects v1.

## EXAMPLES

### EXAMPLE 1

Write-DJMLog -Message 'Sync started' -Level INFO

### EXAMPLE 2

try { ... } catch { Write-DJMLog -Message 'Failed' -Level ERROR -ErrorObject $_ }

## PARAMETERS

### -CallerDepth



```yaml
Type: System.Int32
DefaultValue: 1
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Error
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: Default
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -CorrelationId

Correlate related entries.
Defaults to the active activity's CorrelationId,
falling back to a fresh GUID.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Error
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: Default
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Depth



```yaml
Type: System.Int32
DefaultValue: 8
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Error
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: Default
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ErrorObject

ErrorRecord; only valid when -Level ERROR or FATAL.

```yaml
Type: System.Management.Automation.ErrorRecord
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Error
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Level

Severity.
INFO | WARN | ERROR | DEBUG | FATAL.
Defaults to INFO.

```yaml
Type: System.String
DefaultValue: INFO
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Error
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: Default
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -LogPath

Per-call file-sink override.
When omitted, the module-level value from
Set-DJMLogConfig is used.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Error
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: Default
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -MaxSizeMB

Per-call file-sink overrides.
These are forwarded to the writer as
sidecar fields on the entry; the File sink reads them with fallback
to the module defaults from Set-DJMLogConfig.

```yaml
Type: System.Double
DefaultValue: -1
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Error
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: Default
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Message

The human-readable log message.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Error
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: Default
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Metadata

Optional hashtable / PSCustomObject merged into the entry's Metadata block.

```yaml
Type: System.Management.Automation.PSObject
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Error
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: Default
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -MinLevel

Per-call minimum severity threshold.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Error
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: Default
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -MutexTimeoutMs



```yaml
Type: System.Int32
DefaultValue: -2
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Error
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: Default
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -NoCaller

Suppress caller auto-capture for this call.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Error
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: Default
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -NoHostContext

Suppress Host enrichment for this call.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Error
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: Default
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -PassThru

Emit the entry to the pipeline as a PSCustomObject in addition to enqueueing.
Note: redaction has already been applied to the returned object — values
matching the always-on rules (SecureString / PSCredential / sensitive
metadata keys) and any configured RedactionPatterns / RedactionPresets are
`[REDACTED]` in the PassThru object.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Error
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: Default
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -RetainDays



```yaml
Type: System.Int32
DefaultValue: -1
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Error
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: Default
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -RetainFiles



```yaml
Type: System.Int32
DefaultValue: -1
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Error
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: Default
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -RotationSchedule



```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Error
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: Default
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

### None by default. PSCustomObject when -PassThru is specified.



### System.Management.Automation.PSObject



## NOTES

## RELATED LINKS



