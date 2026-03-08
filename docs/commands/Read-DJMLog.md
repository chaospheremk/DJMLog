---
document type: cmdlet
external help file: DJMLog-Help.xml
HelpUri: ''
Locale: en-US
Module Name: DJMLog
ms.date: 03/08/2026
PlatyPS schema version: 2024-05-01
title: Read-DJMLog
---

# Read-DJMLog

## SYNOPSIS

Reads and filters a JSONL log file produced by Write-DJMLog.

## SYNTAX

### __AllParameterSets

```
Read-DJMLog [[-LogPath] <string>] [[-Level] <string[]>] [[-CorrelationId] <string>]
 [[-MessageContains] <string>] [[-Since] <datetime>] [[-Until] <datetime>] [[-First] <int>]
 [[-Last] <int>] [[-CsvPath] <string>] [-Colorize] [-ExportCsv] [-OutGridView] [-Raw] [-PassThru]
 [<CommonParameters>]
```

## ALIASES

None.

## DESCRIPTION

Streams the target file line by line using `[System.IO.File]::ReadLines`, keeping memory usage flat regardless of file size. Each line is parsed as a JSON object. Lines that cannot be parsed, have an invalid timestamp, or are missing Level or Message are skipped with a warning.

Filtering is applied before object construction. All active filters must match for an entry to be included. -First and -Last are applied after all other filters have been evaluated. -First and -Last cannot be combined; if both are supplied, -First is honoured and a warning is emitted.

**Metadata flattening:**
Nested Metadata properties are recursively promoted to top-level columns using underscore-separated key paths. Flattening descends through all levels of nesting. For example:

- `Metadata.Error.Message` becomes `Error_Message`
- `Metadata.Http.Response.Code` becomes `Http_Response_Code`

**Column normalisation:**
All returned objects are padded with `$null` for any column not present in that specific entry, so every object in the output shares an identical property set. Column order reflects first-seen insertion order across the result set after -First or -Last slicing.

**Output timestamps:**

- **LocalTime** — entry timestamp converted to the local timezone
- **UtcTime** — entry timestamp in UTC

**Output behaviour:**
By default, PSCustomObjects are emitted to the pipeline. When -Colorize, -ExportCsv, or -OutGridView are specified, pipeline output is suppressed unless -PassThru is also present. When -Raw is specified, the unmodified JSON strings are emitted to the pipeline instead of objects. -Colorize, -ExportCsv, and -OutGridView still operate on the parsed objects regardless of -Raw.

## EXAMPLES

### EXAMPLE 1

```powershell
# Return all ERROR entries as objects
$errors = Read-DJMLog -Level ERROR
$errors | Select-Object LocalTime, Message, Error_Message
```

### EXAMPLE 2

```powershell
# Colorized console view filtered by level and time window
Read-DJMLog -Level WARN, ERROR -Since (Get-Date).AddHours(-4) -Colorize
```

### EXAMPLE 3

```powershell
# Filter by message content and export to CSV
Read-DJMLog -MessageContains 'provisioning' -ExportCsv -CsvPath C:\Reports\provision.csv
```

### EXAMPLE 4

```powershell
# Colorize to console and also capture results for further processing
$results = Read-DJMLog -Level ERROR -Colorize -PassThru
$results | Group-Object CorrelationId | Where-Object { $_.Count -gt 1 }
```

### EXAMPLE 5

```powershell
# Retrieve all entries for a specific operation by correlation ID
Read-DJMLog -CorrelationId $cid | Format-Table LocalTime, Level, Message
```

### EXAMPLE 6

```powershell
# Show the 20 most recent entries interactively on Windows
Read-DJMLog -Last 20 -OutGridView
```

### EXAMPLE 7

```powershell
# Emit raw JSON strings for forwarding or external processing
Read-DJMLog -Level ERROR -Raw | Set-Content -LiteralPath C:\export\errors.jsonl
```

## PARAMETERS

### -Colorize

Writes a formatted summary of each matching entry to the host using
colour-coded output: ERROR=Red, WARN=Yellow, DEBUG=DarkGray, INFO=Gray.
Output format: yyyy-MM-dd HH:mm:ss [LVL] Message (local time).
Suppresses pipeline output unless -PassThru is also specified.

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

### -CorrelationId

Restricts output to entries whose CorrelationId exactly matches the
provided string.
Case-sensitive.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 2
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -CsvPath

Destination path for the CSV export.
Only used when -ExportCsv is
specified.
Defaults to log.csv in the current working directory.

```yaml
Type: System.String
DefaultValue: '"$(Get-Location)\log.csv"'
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 8
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ExportCsv

Exports all matching results to a CSV file at -CsvPath after processing
completes.
Suppresses pipeline output unless -PassThru is also specified.

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

### -First

Returns only the first N entries from the filtered result set.
Cannot be
combined with -Last.

```yaml
Type: System.Int32
DefaultValue: 0
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 6
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Last

Returns only the last N entries from the filtered result set.
Cannot be
combined with -First.

```yaml
Type: System.Int32
DefaultValue: 0
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 7
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Level

Restricts output to entries matching one or more severity levels.
Accepts an array.
Case-insensitive.
When omitted, all levels are returned.

```yaml
Type: System.String[]
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

### -LogPath

Path to the JSONL file to read.
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

### -MessageContains

Restricts output to entries whose Message field matches the given wildcard
pattern.
Equivalent to -like "*<value>*".

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 3
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -OutGridView

Sends all matching results to Out-GridView for interactive inspection.
Windows only.
A warning is emitted and the switch is ignored on non-Windows
platforms.
Suppresses pipeline output unless -PassThru is also specified.

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

### -PassThru

When specified alongside -Colorize, -ExportCsv, or -OutGridView, also
emits result objects to the pipeline.
When -Raw is also set, emits JSON
strings.
Has no effect when none of those switches are present, as
pipeline output is the default behaviour in that case.

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

### -Raw

Emits the unmodified JSON strings from the file instead of PSCustomObjects.
Filtering still applies.
-Colorize, -ExportCsv, and -OutGridView continue
to operate on the parsed objects regardless of -Raw.

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

### -Since

Restricts output to entries with a UTC timestamp at or after this value.
The provided datetime is converted to UTC before comparison.

```yaml
Type: System.DateTime
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 4
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Until

Restricts output to entries with a UTC timestamp at or before this value.
The provided datetime is converted to UTC before comparison.

```yaml
Type: System.DateTime
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 5
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

None. This cmdlet does not accept pipeline input.

## OUTPUTS

### PSCustomObject by default. String when -Raw is specified.

Returns deserialized log entries as PSCustomObjects with flattened metadata, or raw JSONL strings when -Raw is specified.

## NOTES

## RELATED LINKS

