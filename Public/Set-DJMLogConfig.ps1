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
            "Path":           "C:\\Logs\\automation.jsonl",
            "MaxSizeMB":      50,
            "MutexTimeoutMs": 2000
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

    .PARAMETER ConfigPath
    Path to a JSON config file. Supported properties are Path, MaxSizeMB, and
    MutexTimeoutMs. Explicit parameters on the same call override values from
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
    #>
    [CmdletBinding()]
    param (
        [string]$Path,

        [double]$MaxSizeMB,

        [int]$MutexTimeoutMs,

        [string]$ConfigPath
    )

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
    if ($PSBoundParameters.ContainsKey('Path')          -or ($ConfigPath -and $null -ne $Path))           { $script:DefaultLogPath         = $Path }
    if ($PSBoundParameters.ContainsKey('MaxSizeMB')     -or ($ConfigPath -and $null -ne $MaxSizeMB))      { $script:DefaultMaxSizeMB       = $MaxSizeMB }
    if ($PSBoundParameters.ContainsKey('MutexTimeoutMs') -or ($ConfigPath -and $null -ne $MutexTimeoutMs)) { $script:DefaultMutexTimeoutMs  = $MutexTimeoutMs }
}
