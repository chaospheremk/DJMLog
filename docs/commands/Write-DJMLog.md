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

Appends a structured entry to a JSONL log file.

## SYNTAX

### Error

```
Write-DJMLog -Message <string> -ErrorObject <ErrorRecord> [-Level <string>]
 [-CorrelationId <string>] [-LogPath <string>] [-Metadata <psobject>] [-MaxSizeMB <double>]
 [-MinLevel <string>] [-RotationSchedule <string>] [-RetainDays <int>] [-RetainFiles <int>]
 [-Depth <int>] [-MutexTimeoutMs <int>] [-CallerDepth <int>] [-NoCaller] [-PassThru]
 [<CommonParameters>]
```

### Default

```
Write-DJMLog -Message <string> [-Level <string>] [-CorrelationId <string>] [-LogPath <string>]
 [-Metadata <psobject>] [-MaxSizeMB <double>] [-MinLevel <string>] [-RotationSchedule <string>]
 [-RetainDays <int>] [-RetainFiles <int>] [-Depth <int>] [-MutexTimeoutMs <int>]
 [-CallerDepth <int>] [-NoCaller] [-PassThru] [<CommonParameters>]
```

## ALIASES

None.
## DESCRIPTION

Writes one JSON object per call to the target file, appending a newline
after each entry.
The log directory is created automatically if it does
not exist.
All timestamps are ISO 8601 UTC.
Writes use
[System.IO.File]::AppendAllText for a shorter file lock window, reducing
collision risk when multiple runspaces write to the same file.

Each log entry always contains:
    UtcTimestamp  - ISO 8601 UTC timestamp of the write
    Level         - Severity level, uppercased
    Message       - The provided message string
    CorrelationId - GUID string linking related entries

Minimum level filtering:
    When a module-level MinLevel has been configured via Set-DJMLogConfig
    (or -MinLevel is passed per-call), entries whose level falls below the
    threshold are silently discarded without acquiring the mutex or touching
    the file.
Level order: DEBUG < INFO < WARN < ERROR.

When -Metadata is provided, its key-value pairs are written under a
nested Metadata object.
Hashtables and PSCustomObjects are both supported.
Any other type is stored under Metadata.RawValue.

Caller auto-capture:
    By default, Write-DJMLog captures the calling script name, function
    name, and line number from the PowerShell call stack and stores them
    under Metadata.Caller.
Use -NoCaller to suppress this for a single
    call, or Set-DJMLogConfig -IncludeCaller $false to disable globally.
    A user-supplied Metadata.Caller value is never overwritten.

When -ErrorObject is provided alongside -Level ERROR, error context is
captured under Metadata.Error with the following fields:
    ScriptName      - Path of the script where the error originated
    LineNumber      - Line number within that script
    Command         - Name of the command that threw
    PositionMessage - First line of the invocation position message
    Type            - Full exception type name (top-level)
    Message         - Exception message text (top-level)
    ExceptionChain  - Array of { Type, Message } for every exception in
                      the InnerException / AggregateException.InnerExceptions
                      chain, outermost first.

Log rotation:
    Size-based: when -MaxSizeMB is greater than zero (or a module-level
    maximum has been configured via Set-DJMLogConfig), Write-DJMLog checks
    the current file size after acquiring the write mutex.
If the file
    meets or exceeds the threshold, it is rotated.

    Time-based: when -RotationSchedule is Daily or Hourly (or configured
    via Set-DJMLogConfig), the file's UTC creation time is compared to the
    current period.
If the file was created in a prior day or hour, it is
    rotated before writing.

    Rotation runs *inside* the named mutex so two runspaces racing across
    the threshold cannot both perform the rename.
The losing runspace
    sees the freshly created (small) file on its post-acquisition recheck
    and proceeds to the append step without rotating.

    The rotated file name uses the pattern:
    <basename>_yyyyMMdd-HHmmss<extension>

Retention cleanup (runs only after a rotation):
    -RetainDays N  - deletes rotated files older than N days.
    -RetainFiles N - keeps only the N most recent rotated files.
    Both can be used together; RetainDays runs first.
    Set either to 0 (the default) to keep all rotated files.

    A failure to delete any individual rotated file (locked, ACL,
    unreadable creation time) is recorded in the SelfLog queue
    (Get-DJMLogDiagnostics) and the cleanup loop continues with the
    remaining files instead of aborting.

A non-terminating warning is emitted if the file cannot be written, if the
mutex timeout expires before the write lock can be acquired, or if
-ErrorObject is supplied without -Level ERROR.
Internal failures are also
enqueued to the SelfLog (Get-DJMLogDiagnostics) so callers can detect
silent drops without parsing warning streams.

Parallel safety:
    All writes are serialised through a named system mutex
    ('DJMLog_WriteAccess').
The mutex is a kernel object, so it coordinates
    correctly across PowerShell runspaces that do not share memory.
Each
    call acquires the mutex, performs the rotation check + rename if
    needed, performs the AppendAllText, and releases the mutex.

    The Log Analytics buffer (when LogAnalyticsEnabled) is guarded by an
    in-process SemaphoreSlim so concurrent writes within the same process
    cannot corrupt the underlying List.

## EXAMPLES

### EXAMPLE 1

# Basic usage with a shared correlation ID across an operation
$cid = (New-Guid).Guid
Write-DJMLog -Message 'Sync started' -Level INFO -CorrelationId $cid
Write-DJMLog -Message 'Sync completed' -Level INFO -CorrelationId $cid

### EXAMPLE 2

# Attach structured metadata to an entry
$cid = (New-Guid).Guid
Write-DJMLog -Message 'User provisioned' -Level INFO -CorrelationId $cid -Metadata @{
    UserPrincipalName = 'jsmith@contoso.com'
    Department        = 'Engineering'
    LicenseSku        = 'ENTERPRISEPREMIUM'
}

### EXAMPLE 3

# Capture a terminating error with full invocation context
$cid = (New-Guid).Guid
try {
    Get-Content -LiteralPath 'C:\missing.txt' -ErrorAction Stop
}
catch {
    Write-DJMLog -Message 'Failed to read config file' -Level ERROR -ErrorObject $_ -CorrelationId $cid
}

### EXAMPLE 4

# Use PassThru to capture the entry object while writing
$entry = Write-DJMLog -Message 'Provisioning started' -Level INFO -PassThru

### EXAMPLE 5

# Configure rotation once via Set-DJMLogConfig; all subsequent calls honour it
Set-DJMLogConfig -Path 'C:\Logs\app.jsonl' -MaxSizeMB 100
Write-DJMLog -Message 'Entry after rotation check'

### EXAMPLE 6

# Per-call level override - suppress this entry when module threshold is lower
Write-DJMLog -Message 'Verbose diagnostic' -Level DEBUG -MinLevel DEBUG

## PARAMETERS

### -CallerDepth

Call stack frame offset for automatic caller capture.
1 (default) records
the direct caller of Write-DJMLog.
Increase this when Write-DJMLog is
wrapped inside a helper function and you want to record that helper's
caller instead.

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

A string used to correlate related log entries across a single operation
or transaction.
Defaults to a freshly generated GUID if not supplied.
Obtain one with (New-Guid).Guid at the start of an operation and pass it
to every Write-DJMLog call within that operation.

```yaml
Type: System.String
DefaultValue: (New-Guid).Guid
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

Maximum depth for JSON serialisation of the log entry.
Deeply nested
metadata objects beyond this depth are truncated by ConvertTo-Json.
Defaults to 5.

```yaml
Type: System.Int32
DefaultValue: 5
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

An ErrorRecord, typically $_ from a catch block.
Only valid when
-Level ERROR is also specified.
Supplying -ErrorObject with any other
level emits a warning and the error context is not captured.
Captures
invocation context and exception details under Metadata.Error.

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

Severity level of the entry.
Must be one of: INFO, WARN, ERROR, DEBUG.
Case-insensitive.
Stored as uppercase.
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

Absolute or relative path to the target JSONL file.
The parent directory
is created if it does not exist.
When omitted, the module-level default
configured by Set-DJMLogConfig is used.
Falls back to log.jsonl in the current
working directory if no default has been set.

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

Maximum file size in megabytes before rotation is triggered.
When the
log file meets or exceeds this size at the start of a call, it is renamed
with a UTC datestamp suffix and a new file is started.
Set to 0 to
disable.
When omitted, the module-level value from Set-DJMLogConfig is used.

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
Mandatory in both parameter sets.

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

An optional hashtable or PSCustomObject carrying supplementary data to
attach to the entry.
Written under a nested Metadata key.
Read-DJMLog
flattens this into top-level properties on the returned objects.

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
Entries whose level is below this
value are silently discarded.
Overrides the module-level default set by
Set-DJMLogConfig for this call only.

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

Maximum time in milliseconds to wait for the write mutex before giving up.
If the timeout expires the entry is discarded and a non-terminating warning
is emitted.
Defaults to 2000ms.
When omitted, the module-level value from
Set-DJMLogConfig is used.
Set to -1 to wait indefinitely.

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

Suppresses automatic caller capture for this call only.
Use
Set-DJMLogConfig -IncludeCaller $false to disable globally.

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

When specified, emits the written log entry as a PSCustomObject to the
pipeline in addition to writing it to disk.
Useful for in-memory audit
trails or assertions in tests.

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

After rotation, delete rotated files older than this many days.
0 keeps
all.
When omitted, the module-level value from Set-DJMLogConfig is used.

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

After rotation, keep only the N most recent rotated files.
0 keeps all.
Applied after -RetainDays.
When omitted, the module-level value is used.

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

Per-call time-based rotation schedule.
Overrides the module-level default
for this call only.
Valid values: None, Daily, Hourly.

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



