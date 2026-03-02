function Set-DJMLogConfig {
    <#
    .SYNOPSIS
    Configures module-level defaults for Write-DJMLog and Read-DJMLog.

    .DESCRIPTION
    Sets module-scoped defaults so that Write-DJMLog and Read-DJMLog callers
    do not need to supply -LogPath, -MaxSizeMB, or -MutexTimeoutMs on every
    call. Settings can be provided directly as parameters, loaded from a JSON
    config file via -ConfigPath, or both.

    Precedence when both -ConfigPath and explicit parameters are supplied:
        Explicit parameter > config file value > existing module default

    Only properties present in the config file are applied. Missing properties
    leave the corresponding module default unchanged. The same rule applies to
    explicit parameters — omitting a parameter does not reset its module default.

    Config file schema (all properties optional):
        {
            "Path":             "C:\\Logs\\automation.jsonl",
            "MaxSizeMB":        50,
            "MutexTimeoutMs":   2000,
            "MinLevel":         "INFO",
            "RotationSchedule": "Daily",
            "RetainDays":       30,
            "RetainFiles":      10,
            "IncludeCaller":    true
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

    .PARAMETER ConfigPath
    Path to a JSON config file. Supported properties: Path, MaxSizeMB,
    MutexTimeoutMs, MinLevel, RotationSchedule, RetainDays, RetainFiles,
    IncludeCaller. Explicit parameters on the same call override values from
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

        [string]$ConfigPath
    )

    $includeCallerSetFromFile = $false

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
            }
            catch {
                Write-Warning "Set-DJMLogConfig: failed to read or parse config file '$ConfigPath': $_"
            }
        }
    }

    # Apply only the values that ended up being set — don't overwrite module
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
}
