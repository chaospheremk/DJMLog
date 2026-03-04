function Set-DJMLogConfig {
    <#
    .SYNOPSIS
    Configures module-level defaults for Write-DJMLog, Read-DJMLog, and Send-DJMLogBuffer.

    .DESCRIPTION
    Sets module-scoped defaults so that Write-DJMLog and Read-DJMLog callers
    do not need to supply -LogPath, -MaxSizeMB, or -MutexTimeoutMs on every
    call. Also configures Azure Log Analytics integration settings for
    Send-DJMLogBuffer. Settings can be provided directly as parameters, loaded
    from a JSON config file via -ConfigPath, or both.

    Precedence when both -ConfigPath and explicit parameters are supplied:
        Explicit parameter > config file value > existing module default

    Only properties present in the config file are applied. Missing properties
    leave the corresponding module default unchanged. The same rule applies to
    explicit parameters -- omitting a parameter does not reset its module default.

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

    .PARAMETER Path
    Absolute or relative path to the default JSONL log file.

    .PARAMETER MaxSizeMB
    Maximum log file size in megabytes before Write-DJMLog triggers rotation.
    When the file reaches or exceeds this size it is renamed with a UTC
    datestamp suffix and a new file is started. Set to 0 to disable rotation.

    .PARAMETER MutexTimeoutMs
    Maximum time in milliseconds that Write-DJMLog will wait to acquire the
    write mutex before giving up and discarding the entry. Set to -1 to wait
    indefinitely, though this risks hanging a runspace if another thread
    crashes while holding the mutex.

    .PARAMETER MinLevel
    Minimum severity level that Write-DJMLog will write. Entries with a level
    below this threshold are silently discarded. Levels in ascending order:
    DEBUG < INFO < WARN < ERROR. Defaults to DEBUG (all entries written).

    .PARAMETER RotationSchedule
    Time-based rotation schedule applied in addition to -MaxSizeMB. When the
    active log file's creation time falls outside the current period, it is
    rotated before the next write. Valid values: None, Daily, Hourly.
    Defaults to None (time-based rotation disabled).

    .PARAMETER RetainDays
    After rotating, delete rotated files whose UTC creation time is older than
    this many days. Set to 0 to keep all rotated files indefinitely.

    .PARAMETER RetainFiles
    After rotating, keep only this many rotated files (the most recent N).
    Older files are deleted. Set to 0 to keep all rotated files indefinitely.
    Applied after -RetainDays when both are set.

    .PARAMETER IncludeCaller
    When $true (the default), Write-DJMLog automatically captures the calling
    script name, function name, and line number and stores them under
    Metadata.Caller. Set to $false to disable this behaviour globally.

    .PARAMETER LogAnalyticsEnabled
    Enables or disables Azure Log Analytics buffer integration. When $true,
    Write-DJMLog adds entries to an in-memory buffer for batch submission.

    .PARAMETER CloudEnvironment
    Azure cloud environment for OAuth2 endpoints and token scope.
    Valid values: Commercial, GCCHigh, DoD. Defaults to GCCHigh.

    .PARAMETER DcrEndpointUri
    Data Collection Endpoint URI for the Logs Ingestion API, e.g.
    'https://my-dce.eastus.ingest.monitor.azure.us'.

    .PARAMETER DcrImmutableId
    Immutable ID of the Data Collection Rule, e.g. 'dcr-abc123'.

    .PARAMETER DcrStreamName
    Stream name declared in the DCR, e.g. 'Custom-MyTable_CL'.

    .PARAMETER TenantId
    Azure AD / Entra ID tenant ID for OAuth2 token acquisition.

    .PARAMETER AppId
    Application (client) ID of the Entra ID app registration.

    .PARAMETER AppSecret
    Client secret for the app registration. Accepts a plain string or
    SecureString. SecureString is converted internally for the OAuth2 flow.
    Use certificate auth in production; this is a dev/test fallback.

    .PARAMETER CertificateSubject
    Certificate subject name (e.g. 'CN=DJMLog-Auth') used for JWT assertion
    authentication. The best matching certificate (latest NotAfter, not
    expired, has private key) is selected from LocalMachine\My then
    CurrentUser\My. Primary authentication method for production.

    .PARAMETER CertificateThumbprint
    Certificate thumbprint to pin authentication to a specific certificate.
    Searched in LocalMachine\My then CurrentUser\My.

    .PARAMETER BearerToken
    Pre-acquired bearer token (e.g. from a managed identity). When set, all
    other auth settings are bypassed. The caller manages token expiry.

    .PARAMETER FlushThreshold
    Number of buffered entries that triggers an automatic flush via
    Send-DJMLogBuffer. Defaults to 100.

    .PARAMETER MaxBufferSize
    Maximum number of entries the buffer can hold. When reached, the oldest
    entry is dropped with a warning. Defaults to 5000.

    .PARAMETER MaxFlushRetries
    Number of consecutive flush failures before the auto-flush circuit breaker
    trips. Use Send-DJMLogBuffer -Force to override. Defaults to 3.

    .PARAMETER ConfigPath
    Path to a JSON config file. All parameters above are supported as
    properties. Explicit parameters on the same call override values from
    the file. A non-terminating warning is emitted if the file cannot be read
    or does not contain valid JSON.

    .EXAMPLE
    # Configure directly with parameters
    Set-DJMLogConfig -Path 'C:\Logs\automation.jsonl' -MaxSizeMB 50

    .EXAMPLE
    # Load all settings from a config file
    Set-DJMLogConfig -ConfigPath 'C:\Config\logconfig.json'

    .EXAMPLE
    # Load from file but override the path for this environment
    Set-DJMLogConfig -ConfigPath 'C:\Config\logconfig.json' -Path 'D:\Logs\automation.jsonl'

    .EXAMPLE
    # Only write WARN and above; rotate daily; keep last 14 rotated files
    Set-DJMLogConfig -MinLevel WARN -RotationSchedule Daily -RetainFiles 14

    .EXAMPLE
    # Disable automatic caller capture
    Set-DJMLogConfig -IncludeCaller $false

    .EXAMPLE
    # Enable Log Analytics with certificate authentication
    Set-DJMLogConfig -LogAnalyticsEnabled $true -CloudEnvironment GCCHigh `
        -DcrEndpointUri 'https://my-dce.eastus.ingest.monitor.azure.us' `
        -DcrImmutableId 'dcr-abc123' -DcrStreamName 'Custom-MyTable_CL' `
        -TenantId '00000000-...' -AppId '11111111-...' `
        -CertificateSubject 'CN=DJMLog-Auth'

    .EXAMPLE
    # Enable Log Analytics with a pre-acquired bearer token
    Set-DJMLogConfig -LogAnalyticsEnabled $true `
        -DcrEndpointUri 'https://my-dce.eastus.ingest.monitor.azure.us' `
        -DcrImmutableId 'dcr-abc123' -DcrStreamName 'Custom-MyTable_CL' `
        -BearerToken $myToken
    #>
    [CmdletBinding()]
    param (
        [string]$Path,

        [double]$MaxSizeMB,

        [int]$MutexTimeoutMs,

        [ValidateSet("DEBUG", "INFO", "WARN", "ERROR", IgnoreCase = $true)]
        [string]$MinLevel,

        [ValidateSet("None", "Daily", "Hourly", IgnoreCase = $true)]
        [string]$RotationSchedule,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$RetainDays,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$RetainFiles,

        [bool]$IncludeCaller,

        [bool]$LogAnalyticsEnabled,

        [ValidateSet("Commercial", "GCCHigh", "DoD", IgnoreCase = $true)]
        [string]$CloudEnvironment,

        [string]$DcrEndpointUri,

        [string]$DcrImmutableId,

        [string]$DcrStreamName,

        [string]$TenantId,

        [string]$AppId,

        [PSObject]$AppSecret,

        [string]$CertificateSubject,

        [string]$CertificateThumbprint,

        [string]$BearerToken,

        [ValidateRange(1, [int]::MaxValue)]
        [int]$FlushThreshold,

        [ValidateRange(1, [int]::MaxValue)]
        [int]$MaxBufferSize,

        [ValidateRange(1, [int]::MaxValue)]
        [int]$MaxFlushRetries,

        [string]$ConfigPath
    )

    $includeCallerSetFromFile   = $false
    $laEnabledSetFromFile       = $false
    $laParamTouched             = $false

    # Load config file first so explicit parameters can override its values
    if ($ConfigPath) {
        if (-not (Test-Path -LiteralPath $ConfigPath)) {
            Write-Warning "Set-DJMLogConfig: config file not found at '$ConfigPath'."
        }
        else {
            try {
                $fileConfig = Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction Stop |
                              ConvertFrom-Json -ErrorAction Stop

                # Apply file values only for properties not supplied as explicit parameters
                if ($fileConfig.PSObject.Properties['Path'] -and -not $PSBoundParameters.ContainsKey('Path')) {
                    $Path = $fileConfig.Path
                }
                if ($fileConfig.PSObject.Properties['MaxSizeMB'] -and -not $PSBoundParameters.ContainsKey('MaxSizeMB')) {
                    $MaxSizeMB = $fileConfig.MaxSizeMB
                }
                if ($fileConfig.PSObject.Properties['MutexTimeoutMs'] -and -not $PSBoundParameters.ContainsKey('MutexTimeoutMs')) {
                    $MutexTimeoutMs = $fileConfig.MutexTimeoutMs
                }
                if ($fileConfig.PSObject.Properties['MinLevel'] -and -not $PSBoundParameters.ContainsKey('MinLevel')) {
                    $MinLevel = $fileConfig.MinLevel
                }
                if ($fileConfig.PSObject.Properties['RotationSchedule'] -and -not $PSBoundParameters.ContainsKey('RotationSchedule')) {
                    $RotationSchedule = $fileConfig.RotationSchedule
                }
                if ($fileConfig.PSObject.Properties['RetainDays'] -and -not $PSBoundParameters.ContainsKey('RetainDays')) {
                    $RetainDays = [int]$fileConfig.RetainDays
                }
                if ($fileConfig.PSObject.Properties['RetainFiles'] -and -not $PSBoundParameters.ContainsKey('RetainFiles')) {
                    $RetainFiles = [int]$fileConfig.RetainFiles
                }
                if ($fileConfig.PSObject.Properties['IncludeCaller'] -and -not $PSBoundParameters.ContainsKey('IncludeCaller')) {
                    $IncludeCaller = [bool]$fileConfig.IncludeCaller
                    $includeCallerSetFromFile = $true
                }
                if ($fileConfig.PSObject.Properties['LogAnalyticsEnabled'] -and -not $PSBoundParameters.ContainsKey('LogAnalyticsEnabled')) {
                    $LogAnalyticsEnabled = [bool]$fileConfig.LogAnalyticsEnabled
                    $laEnabledSetFromFile = $true
                }
                if ($fileConfig.PSObject.Properties['CloudEnvironment'] -and -not $PSBoundParameters.ContainsKey('CloudEnvironment')) {
                    $CloudEnvironment = $fileConfig.CloudEnvironment
                }
                if ($fileConfig.PSObject.Properties['DcrEndpointUri'] -and -not $PSBoundParameters.ContainsKey('DcrEndpointUri')) {
                    $DcrEndpointUri = $fileConfig.DcrEndpointUri
                }
                if ($fileConfig.PSObject.Properties['DcrImmutableId'] -and -not $PSBoundParameters.ContainsKey('DcrImmutableId')) {
                    $DcrImmutableId = $fileConfig.DcrImmutableId
                }
                if ($fileConfig.PSObject.Properties['DcrStreamName'] -and -not $PSBoundParameters.ContainsKey('DcrStreamName')) {
                    $DcrStreamName = $fileConfig.DcrStreamName
                }
                if ($fileConfig.PSObject.Properties['TenantId'] -and -not $PSBoundParameters.ContainsKey('TenantId')) {
                    $TenantId = $fileConfig.TenantId
                }
                if ($fileConfig.PSObject.Properties['AppId'] -and -not $PSBoundParameters.ContainsKey('AppId')) {
                    $AppId = $fileConfig.AppId
                }
                if ($fileConfig.PSObject.Properties['AppSecret'] -and -not $PSBoundParameters.ContainsKey('AppSecret')) {
                    $AppSecret = $fileConfig.AppSecret
                }
                if ($fileConfig.PSObject.Properties['CertificateSubject'] -and -not $PSBoundParameters.ContainsKey('CertificateSubject')) {
                    $CertificateSubject = $fileConfig.CertificateSubject
                }
                if ($fileConfig.PSObject.Properties['CertificateThumbprint'] -and -not $PSBoundParameters.ContainsKey('CertificateThumbprint')) {
                    $CertificateThumbprint = $fileConfig.CertificateThumbprint
                }
                if ($fileConfig.PSObject.Properties['BearerToken'] -and -not $PSBoundParameters.ContainsKey('BearerToken')) {
                    $BearerToken = $fileConfig.BearerToken
                }
                if ($fileConfig.PSObject.Properties['FlushThreshold'] -and -not $PSBoundParameters.ContainsKey('FlushThreshold')) {
                    $FlushThreshold = [int]$fileConfig.FlushThreshold
                }
                if ($fileConfig.PSObject.Properties['MaxBufferSize'] -and -not $PSBoundParameters.ContainsKey('MaxBufferSize')) {
                    $MaxBufferSize = [int]$fileConfig.MaxBufferSize
                }
                if ($fileConfig.PSObject.Properties['MaxFlushRetries'] -and -not $PSBoundParameters.ContainsKey('MaxFlushRetries')) {
                    $MaxFlushRetries = [int]$fileConfig.MaxFlushRetries
                }
            }
            catch {
                Write-Warning "Set-DJMLogConfig: failed to read or parse config file '$ConfigPath': $_"
            }
        }
    }

    # Apply only the values that ended up being set -- don't overwrite module
    # defaults for parameters that were neither supplied nor present in the file.
    # Null checks are used for the config file branch rather than truthiness so
    # that legitimate zero values (e.g. MaxSizeMB = 0 to disable rotation) are
    # not silently ignored.
    if ($PSBoundParameters.ContainsKey('Path')             -or ($ConfigPath -and $null -ne $Path))             { $script:DefaultLogPath          = $Path }
    if ($PSBoundParameters.ContainsKey('MaxSizeMB')        -or ($ConfigPath -and $null -ne $MaxSizeMB))        { $script:DefaultMaxSizeMB        = $MaxSizeMB }
    if ($PSBoundParameters.ContainsKey('MutexTimeoutMs')   -or ($ConfigPath -and $null -ne $MutexTimeoutMs))   { $script:DefaultMutexTimeoutMs   = $MutexTimeoutMs }
    if ($PSBoundParameters.ContainsKey('MinLevel')         -or ($ConfigPath -and $null -ne $MinLevel))         { $script:DefaultMinLevel         = $MinLevel.ToUpperInvariant() }
    if ($PSBoundParameters.ContainsKey('RotationSchedule') -or ($ConfigPath -and $null -ne $RotationSchedule)) { $script:DefaultRotationSchedule = $RotationSchedule }
    if ($PSBoundParameters.ContainsKey('RetainDays')       -or ($ConfigPath -and $null -ne $RetainDays))       { $script:DefaultRetainDays       = $RetainDays }
    if ($PSBoundParameters.ContainsKey('RetainFiles')      -or ($ConfigPath -and $null -ne $RetainFiles))      { $script:DefaultRetainFiles      = $RetainFiles }
    if ($PSBoundParameters.ContainsKey('IncludeCaller')    -or $includeCallerSetFromFile)                      { $script:DefaultIncludeCaller    = $IncludeCaller }

    # Log Analytics parameters
    if ($PSBoundParameters.ContainsKey('LogAnalyticsEnabled') -or $laEnabledSetFromFile) {
        $script:LogAnalyticsEnabled = $LogAnalyticsEnabled
        $laParamTouched = $true
    }
    if ($PSBoundParameters.ContainsKey('CloudEnvironment')    -or ($ConfigPath -and $null -ne $CloudEnvironment)) {
        $script:CloudEnvironment = $CloudEnvironment
        $laParamTouched = $true
    }
    if ($PSBoundParameters.ContainsKey('DcrEndpointUri')      -or ($ConfigPath -and $null -ne $DcrEndpointUri)) {
        $script:DcrEndpointUri = $DcrEndpointUri
        $laParamTouched = $true
    }
    if ($PSBoundParameters.ContainsKey('DcrImmutableId')      -or ($ConfigPath -and $null -ne $DcrImmutableId)) {
        $script:DcrImmutableId = $DcrImmutableId
        $laParamTouched = $true
    }
    if ($PSBoundParameters.ContainsKey('DcrStreamName')       -or ($ConfigPath -and $null -ne $DcrStreamName)) {
        $script:DcrStreamName = $DcrStreamName
        $laParamTouched = $true
    }
    if ($PSBoundParameters.ContainsKey('TenantId')            -or ($ConfigPath -and $null -ne $TenantId)) {
        $script:TenantId = $TenantId
        $laParamTouched = $true
    }
    if ($PSBoundParameters.ContainsKey('AppId')               -or ($ConfigPath -and $null -ne $AppId)) {
        $script:AppId = $AppId
        $laParamTouched = $true
    }
    if ($PSBoundParameters.ContainsKey('AppSecret')           -or ($ConfigPath -and $null -ne $AppSecret)) {
        # Convert SecureString to SecureString (keep as-is); convert plain string to store directly
        if ($AppSecret -is [System.Security.SecureString]) {
            $script:AppSecret = $AppSecret
        }
        else {
            $script:AppSecret = [string]$AppSecret
        }
        $laParamTouched = $true
    }
    if ($PSBoundParameters.ContainsKey('CertificateSubject')  -or ($ConfigPath -and $null -ne $CertificateSubject)) {
        $script:CertificateSubject = $CertificateSubject
        $laParamTouched = $true
    }
    if ($PSBoundParameters.ContainsKey('CertificateThumbprint') -or ($ConfigPath -and $null -ne $CertificateThumbprint)) {
        $script:CertificateThumbprint = $CertificateThumbprint
        $laParamTouched = $true
    }
    if ($PSBoundParameters.ContainsKey('BearerToken')         -or ($ConfigPath -and $null -ne $BearerToken)) {
        $script:BearerTokenExternal = $BearerToken
        $laParamTouched = $true
    }
    if ($PSBoundParameters.ContainsKey('FlushThreshold')      -or ($ConfigPath -and $null -ne $FlushThreshold)) {
        $script:FlushThreshold = $FlushThreshold
        $laParamTouched = $true
    }
    if ($PSBoundParameters.ContainsKey('MaxBufferSize')       -or ($ConfigPath -and $null -ne $MaxBufferSize)) {
        $script:MaxBufferSize = $MaxBufferSize
        $laParamTouched = $true
    }
    if ($PSBoundParameters.ContainsKey('MaxFlushRetries')     -or ($ConfigPath -and $null -ne $MaxFlushRetries)) {
        $script:MaxFlushRetries = $MaxFlushRetries
        $laParamTouched = $true
    }

    # Reset circuit breaker when any LA param is changed
    if ($laParamTouched) {
        $script:FlushFailureCount = 0
        $script:AutoFlushDisabled = $false
    }
}
