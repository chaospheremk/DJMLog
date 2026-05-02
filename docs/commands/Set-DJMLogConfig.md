---
document type: cmdlet
external help file: DJMLog-Help.xml
HelpUri: ''
Locale: en-US
Module Name: DJMLog
ms.date: 01/01/1970
PlatyPS schema version: 2024-05-01
title: Set-DJMLogConfig
---

# Set-DJMLogConfig

## SYNOPSIS

Configures module-level defaults for Write-DJMLog, Read-DJMLog, and Send-DJMLogBuffer.

## SYNTAX

### __AllParameterSets

```
Set-DJMLogConfig [[-Path] <string>] [[-MaxSizeMB] <double>] [[-MutexTimeoutMs] <int>]
 [[-MinLevel] <string>] [[-RotationSchedule] <string>] [[-RetainDays] <int>] [[-RetainFiles] <int>]
 [[-IncludeCaller] <bool>] [[-LogAnalyticsEnabled] <bool>] [[-CloudEnvironment] <string>]
 [[-DcrEndpointUri] <string>] [[-DcrImmutableId] <string>] [[-DcrStreamName] <string>]
 [[-TenantId] <string>] [[-AppId] <string>] [[-AppSecret] <psobject>]
 [[-CertificateSubject] <string>] [[-CertificateThumbprint] <string>] [[-BearerToken] <string>]
 [[-ManagedIdentityClientId] <string>] [[-FlushThreshold] <int>] [[-MaxBufferSize] <int>]
 [[-MaxBufferBytes] <long>] [[-MaxFlushRetries] <int>] [[-ChannelCapacity] <int>]
 [[-Sinks] <string[]>] [[-RedactionPatterns] <string[]>] [[-RedactionPresets] <string[]>]
 [[-SampleRate] <hashtable>] [[-IncludeHostContext] <bool>] [[-ConfigPath] <string>]
 [-UseManagedIdentity] [<CommonParameters>]
```

## ALIASES

None.
## DESCRIPTION

Sets module-scoped defaults so that Write-DJMLog and Read-DJMLog callers
do not need to supply -LogPath, -MaxSizeMB, or -MutexTimeoutMs on every
call.
Also configures Azure Log Analytics integration settings for
Send-DJMLogBuffer.
Settings can be provided directly as parameters, loaded
from a JSON config file via -ConfigPath, or both.

Precedence when both -ConfigPath and explicit parameters are supplied:
    Explicit parameter > config file value > existing module default

Only properties present in the config file are applied.
Missing properties
leave the corresponding module default unchanged.
The same rule applies to
explicit parameters -- omitting a parameter does not reset its module default.

Log Analytics validation:
    When LogAnalyticsEnabled is $true (either set on this call or already
    on from a prior call), the cmdlet validates that DcrEndpointUri,
    DcrImmutableId, DcrStreamName, and an authentication method are all
    configured.
Missing fields surface as a single non-terminating error
    listing every gap.
Supplied parameters are still committed to module
    state -- callers may complete the configuration on a follow-up call
    without restarting -- but Send-DJMLogBuffer will fail at flush time
    until every required field is in place.

When any Log Analytics parameter is set, the circuit breaker state is reset
(FlushFailureCount = 0, AutoFlushDisabled = $false).

Config file schema (all properties optional):
    {
        "Path":                  "C:\\Logs\\automation.jsonl",
        "MaxSizeMB":            50,
        "MutexTimeoutMs":       2000,
        "MinLevel":             "INFO",
        "RotationSchedule":     "Daily",
        "RetainDays":           30,
        "RetainFiles":          10,
        "IncludeCaller":        true,
        "LogAnalyticsEnabled":  true,
        "CloudEnvironment":     "GCCHigh",
        "DcrEndpointUri":       "https://my-dce.eastus.ingest.monitor.azure.us",
        "DcrImmutableId":       "dcr-abc123",
        "DcrStreamName":        "Custom-MyTable_CL",
        "TenantId":             "00000000-0000-0000-0000-000000000000",
        "AppId":                "00000000-0000-0000-0000-000000000000",
        "AppSecret":            "secret",
        "CertificateSubject":   "CN=DJMLog-Auth",
        "CertificateThumbprint":"AABBCC...",
        "BearerToken":          "eyJ...",
        "FlushThreshold":       100,
        "MaxBufferSize":        5000,
        "MaxFlushRetries":      3
    }

Unknown properties in the config file are silently ignored.

## EXAMPLES

### EXAMPLE 1

# Configure directly with parameters
Set-DJMLogConfig -Path 'C:\Logs\automation.jsonl' -MaxSizeMB 50

### EXAMPLE 2

# Load all settings from a config file
Set-DJMLogConfig -ConfigPath 'C:\Config\logconfig.json'

### EXAMPLE 3

# Load from file but override the path for this environment
Set-DJMLogConfig -ConfigPath 'C:\Config\logconfig.json' -Path 'D:\Logs\automation.jsonl'

### EXAMPLE 4

# Only write WARN and above; rotate daily; keep last 14 rotated files
Set-DJMLogConfig -MinLevel WARN -RotationSchedule Daily -RetainFiles 14

### EXAMPLE 5

# Disable automatic caller capture
Set-DJMLogConfig -IncludeCaller $false

### EXAMPLE 6

# Enable Log Analytics with certificate authentication
$params = @{
    LogAnalyticsEnabled = $true
    CloudEnvironment    = 'GCCHigh'
    DcrEndpointUri      = 'https://my-dce.eastus.ingest.monitor.azure.us'
    DcrImmutableId      = 'dcr-abc123'
    DcrStreamName       = 'Custom-MyTable_CL'
    TenantId            = '00000000-...'
    AppId               = '11111111-...'
    CertificateSubject  = 'CN=DJMLog-Auth'
}
Set-DJMLogConfig @params

### EXAMPLE 7

# Enable Log Analytics with a pre-acquired bearer token
$params = @{
    LogAnalyticsEnabled = $true
    DcrEndpointUri      = 'https://my-dce.eastus.ingest.monitor.azure.us'
    DcrImmutableId      = 'dcr-abc123'
    DcrStreamName       = 'Custom-MyTable_CL'
    BearerToken         = $myToken
}
Set-DJMLogConfig @params

## PARAMETERS

### -AppId

Application (client) ID of the Entra ID app registration.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 14
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -AppSecret

Client secret for the app registration.
SecureString input is preferred
and is stored as-is.
Plain-string input is accepted for back-compat but
converted to a SecureString on assignment so the module never retains the
plaintext at script scope.
The plain-string input path is deprecated and
will be removed in v2.x — pass [SecureString] going forward.
Use certificate auth in production; this is a dev/test fallback.

```yaml
Type: System.Management.Automation.PSObject
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 15
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -BearerToken

Pre-acquired bearer token (e.g.
from a managed identity).
When set, all
other auth settings are bypassed.
The caller manages token expiry.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 18
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -CertificateSubject

Certificate subject name (e.g.
'CN=DJMLog-Auth') used for JWT assertion
authentication.
The best matching certificate (latest NotAfter, not
expired, has private key) is selected from LocalMachine\My then
CurrentUser\My.
Primary authentication method for production.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 16
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -CertificateThumbprint

Certificate thumbprint to pin authentication to a specific certificate.
Searched in LocalMachine\My then CurrentUser\My.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 17
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ChannelCapacity

Bounded capacity of the async writer channel (v2.0).
When the channel is at
capacity, the oldest entry is dropped (FullMode=DropOldest).
The drop is
surfaced via Get-DJMLogDiagnostics.DroppedCount.
Defaults to 10000.

```yaml
Type: System.Int32
DefaultValue: 0
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 24
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -CloudEnvironment

Azure cloud environment for OAuth2 endpoints and token scope.
Valid values: Commercial, GCCHigh, DoD.
Defaults to GCCHigh.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 9
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ConfigPath

Path to a JSON config file.
All parameters above are supported as
properties.
Explicit parameters on the same call override values from
the file.
A non-terminating warning is emitted if the file cannot be read
or does not contain valid JSON.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 30
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -DcrEndpointUri

Data Collection Endpoint URI for the Logs Ingestion API, e.g.
'https://my-dce.eastus.ingest.monitor.azure.us'.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 10
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -DcrImmutableId

Immutable ID of the Data Collection Rule, e.g.
'dcr-abc123'.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 11
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -DcrStreamName

Stream name declared in the DCR, e.g.
'Custom-MyTable_CL'.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 12
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -FlushThreshold

Number of buffered entries that triggers an automatic flush via
Send-DJMLogBuffer.
Defaults to 100.

```yaml
Type: System.Int32
DefaultValue: 0
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 20
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -IncludeCaller

When $true (the default), Write-DJMLog automatically captures the calling
script name, function name, and line number and stores them under
Metadata.Caller.
Set to $false to disable this behaviour globally.

```yaml
Type: System.Boolean
DefaultValue: False
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

### -IncludeHostContext

When $true (the default), v2.0 entries include a Host enrichment block
({ MachineName, ProcessId, UserName, PSVersion }).
Set to $false to
suppress globally.

```yaml
Type: System.Boolean
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 29
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -LogAnalyticsEnabled

Enables or disables Azure Log Analytics buffer integration.
When $true,
Write-DJMLog adds entries to an in-memory buffer for batch submission.

```yaml
Type: System.Boolean
DefaultValue: False
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

### -ManagedIdentityClientId

Optional user-assigned managed-identity client ID.
Forwarded to IMDS as the
`client_id` query parameter.
Ignored when -UseManagedIdentity is not set.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 19
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -MaxBufferBytes

Maximum total serialised size of the buffer in bytes.
When adding a new
entry would push the running total past this cap, the oldest entries are
dropped (FIFO) until the new entry fits.
Set to 0 to disable the byte
cap (count cap from MaxBufferSize still applies).
Defaults to 52428800
bytes (50 MB).

```yaml
Type: System.Int64
DefaultValue: 0
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 22
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -MaxBufferSize

Maximum number of entries the buffer can hold.
When reached, the oldest
entry is dropped with a warning.
Defaults to 5000.

```yaml
Type: System.Int32
DefaultValue: 0
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 21
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -MaxFlushRetries

Number of consecutive flush failures before the auto-flush circuit breaker
trips.
Use Send-DJMLogBuffer -Force to override.
Defaults to 3.

```yaml
Type: System.Int32
DefaultValue: 0
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 23
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -MaxSizeMB

Maximum log file size in megabytes before Write-DJMLog triggers rotation.
When the file reaches or exceeds this size it is renamed with a UTC
datestamp suffix and a new file is started.
Set to 0 to disable rotation.

```yaml
Type: System.Double
DefaultValue: 0
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

### -MinLevel

Minimum severity level that Write-DJMLog will write.
Entries with a level
below this threshold are silently discarded.
Levels in ascending order:
DEBUG < INFO < WARN < ERROR.
Defaults to DEBUG (all entries written).

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

### -MutexTimeoutMs

Maximum time in milliseconds that Write-DJMLog will wait to acquire the
write mutex before giving up and discarding the entry.
Set to -1 to wait
indefinitely, though this risks hanging a runspace if another thread
crashes while holding the mutex.

```yaml
Type: System.Int32
DefaultValue: 0
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

### -Path

Absolute or relative path to the default JSONL log file.

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

### -RedactionPatterns

Array of regex patterns.
Each match in any string metadata value is replaced
with '[REDACTED]'.
Always-on rules (SecureString, PSCredential, sensitive
key names) apply regardless.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 26
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -RedactionPresets

Array of built-in redaction presets: 'Email', 'BearerToken', 'CreditCard'.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 27
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -RetainDays

After rotating, delete rotated files whose UTC creation time is older than
this many days.
Set to 0 to keep all rotated files indefinitely.

```yaml
Type: System.Int32
DefaultValue: 0
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

### -RetainFiles

After rotating, keep only this many rotated files (the most recent N).
Older files are deleted.
Set to 0 to keep all rotated files indefinitely.
Applied after -RetainDays when both are set.

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

### -RotationSchedule

Time-based rotation schedule applied in addition to -MaxSizeMB.
When the
active log file's creation time falls outside the current period, it is
rotated before the next write.
Valid values: None, Daily, Hourly.
Defaults to None (time-based rotation disabled).

```yaml
Type: System.String
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

### -SampleRate

Hashtable @{ <Level> = <0..1 rate> } applied after MinLevel filtering.
A
rate of 0.0 drops all entries at that level; 1.0 keeps all (the default
when omitted).

```yaml
Type: System.Collections.Hashtable
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 28
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Sinks

Array of enabled sinks.
Any combination of 'File', 'Console', 'EventLog',
'LogAnalytics'.
Defaults to @('File').

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 25
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -TenantId

Azure AD / Entra ID tenant ID for OAuth2 token acquisition.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 13
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -UseManagedIdentity

Acquire bearer tokens from the Azure Instance Metadata Service (IMDS,
169.254.169.254) instead of via certificate or client secret.
Suitable for
Azure-hosted workloads (VM, App Service / Functions, Container Apps, AKS).
System-assigned MI is used by default; pass -ManagedIdentityClientId for a
user-assigned MI.
The MI must hold the `Monitoring Metrics Publisher` role
on the Data Collection Rule.
ADR-029.

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

## RELATED LINKS



