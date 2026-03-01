function Write-DJMLog {
    <#
    .SYNOPSIS
    Appends a structured entry to a JSONL log file.

    .DESCRIPTION
    Writes one JSON object per call to the target file, appending a newline
    after each entry. The log directory is created automatically if it does
    not exist. All timestamps are ISO 8601 UTC. Writes use
    [System.IO.File]::AppendAllText for a shorter file lock window, reducing
    collision risk when multiple runspaces write to the same file.

    Each log entry always contains:
        UtcTimestamp  — ISO 8601 UTC timestamp of the write
        Level         — Severity level, uppercased
        Message       — The provided message string
        CorrelationId — GUID string linking related entries

    When -Metadata is provided, its key-value pairs are written under a
    nested Metadata object. Hashtables and PSCustomObjects are both supported.
    Any other type is stored under Metadata.RawValue.

    When -ErrorObject is provided alongside -Level ERROR, error context is
    captured under Metadata.Error with the following fields:
        ScriptName      — Path of the script where the error originated
        LineNumber      — Line number within that script
        Command         — Name of the command that threw
        PositionMessage — First line of the invocation position message
        Type            — Full exception type name
        Message         — Exception message text

    Log rotation:
        When -MaxSizeMB is greater than zero (or a module-level maximum has
        been configured via Set-DJMLogConfig), Write-DJMLog checks the current file
        size at the start of each call. If the file meets or exceeds the
        threshold, it is renamed with a UTC datestamp suffix and a fresh file
        is started. The rotated file name uses the pattern:
        <basename>_yyyyMMdd-HHmmss<extension>

    A non-terminating warning is emitted if the file cannot be written, if the
    mutex timeout expires before the write lock can be acquired, or if
    -ErrorObject is supplied without -Level ERROR.

    Parallel safety:
        All writes are serialised through a named system mutex
        ('DJMLog_WriteAccess'). The mutex is a kernel object, so it coordinates
        correctly across PowerShell runspaces that do not share memory. Each
        call acquires the mutex, performs the AppendAllText, and immediately
        releases it, keeping the lock window as short as possible.

    .PARAMETER Message
    The human-readable log message. Mandatory in both parameter sets.

    .PARAMETER Level
    Severity level of the entry. Must be one of: INFO, WARN, ERROR, DEBUG.
    Case-insensitive. Stored as uppercase. Defaults to INFO.

    .PARAMETER CorrelationId
    A string used to correlate related log entries across a single operation
    or transaction. Defaults to a freshly generated GUID if not supplied.
    Obtain one with (New-Guid).Guid at the start of an operation and pass it
    to every Write-DJMLog call within that operation.

    .PARAMETER LogPath
    Absolute or relative path to the target JSONL file. The parent directory
    is created if it does not exist. When omitted, the module-level default
    configured by Set-DJMLogConfig is used. Falls back to log.jsonl in the current
    working directory if no default has been set.

    .PARAMETER Metadata
    An optional hashtable or PSCustomObject carrying supplementary data to
    attach to the entry. Written under a nested Metadata key. Read-DJMLog
    flattens this into top-level properties on the returned objects.

    .PARAMETER ErrorObject
    An ErrorRecord, typically $_ from a catch block. Only valid when
    -Level ERROR is also specified. Supplying -ErrorObject with any other
    level emits a warning and the error context is not captured. Captures
    invocation context and exception details under Metadata.Error.

    .PARAMETER MaxSizeMB
    Maximum file size in megabytes before rotation is triggered. When the
    log file meets or exceeds this size at the start of a call, it is renamed
    with a UTC datestamp suffix and a new file is started. Set to 0 to
    disable. When omitted, the module-level value from Set-DJMLogConfig is used.

    .PARAMETER Depth
    Maximum depth for JSON serialisation of the log entry. Deeply nested
    metadata objects beyond this depth are truncated by ConvertTo-Json.
    Defaults to 5.

    .PARAMETER MutexTimeoutMs
    Maximum time in milliseconds to wait for the write mutex before giving up.
    If the timeout expires the entry is discarded and a non-terminating warning
    is emitted. Defaults to 2000ms. When omitted, the module-level value from
    Set-DJMLogConfig is used. Set to -1 to wait indefinitely.

    .PARAMETER PassThru
    When specified, emits the written log entry as a PSCustomObject to the
    pipeline in addition to writing it to disk. Useful for in-memory audit
    trails or assertions in tests.

    .OUTPUTS
    None by default. PSCustomObject when -PassThru is specified.

    .EXAMPLE
    # Basic usage with a shared correlation ID across an operation
    $cid = (New-Guid).Guid
    Write-DJMLog -Message 'Sync started' -Level INFO -CorrelationId $cid
    Write-DJMLog -Message 'Sync completed' -Level INFO -CorrelationId $cid

    .EXAMPLE
    # Attach structured metadata to an entry
    $cid = (New-Guid).Guid
    Write-DJMLog -Message 'User provisioned' -Level INFO -CorrelationId $cid -Metadata @{
        UserPrincipalName = 'jsmith@contoso.com'
        Department        = 'Engineering'
        LicenseSku        = 'ENTERPRISEPREMIUM'
    }

    .EXAMPLE
    # Capture a terminating error with full invocation context
    $cid = (New-Guid).Guid
    try {
        Get-Content -LiteralPath 'C:\missing.txt' -ErrorAction Stop
    }
    catch {
        Write-DJMLog -Message 'Failed to read config file' -Level ERROR -ErrorObject $_ -CorrelationId $cid
    }

    .EXAMPLE
    # Use PassThru to capture the entry object while writing
    $entry = Write-DJMLog -Message 'Provisioning started' -Level INFO -PassThru

    .EXAMPLE
    # Configure rotation once via Set-DJMLogConfig; all subsequent calls honour it
    Set-DJMLogConfig -Path 'C:\Logs\app.jsonl' -MaxSizeMB 100
    Write-DJMLog -Message 'Entry after rotation check'
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory, ParameterSetName = 'Default')]
        [Parameter(Mandatory, ParameterSetName = 'Error')]
        [string]$Message,

        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'Error')]
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG", IgnoreCase = $true)]
        [string]$Level = "INFO",

        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'Error')]
        [string]$CorrelationId = (New-Guid).Guid,

        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'Error')]
        [string]$LogPath,

        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'Error')]
        [PSObject]$Metadata,

        [Parameter(Mandatory, ParameterSetName = 'Error')]
        [System.Management.Automation.ErrorRecord]$ErrorObject,

        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'Error')]
        [double]$MaxSizeMB = -1,

        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'Error')]
        [ValidateRange(1, 100)]
        [int]$Depth = 5,

        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'Error')]
        [int]$MutexTimeoutMs = -2,

        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'Error')]
        [switch]$PassThru
    )

    begin {
        # Resolve effective log path: explicit parameter > module default > cwd fallback
        if (-not $LogPath) {
            $LogPath = if ($script:DefaultLogPath) { $script:DefaultLogPath }
                       else { "$(Get-Location)\log.jsonl" }
        }

        # Resolve effective max size: explicit parameter (-1 sentinel) > module default
        $effectiveMaxSizeMB = if ($MaxSizeMB -ge 0) { $MaxSizeMB } else { $script:DefaultMaxSizeMB }

        # Resolve effective mutex timeout: explicit parameter (-2 sentinel) > module default
        $effectiveMutexTimeoutMs = if ($MutexTimeoutMs -ne -2) { $MutexTimeoutMs } else { $script:DefaultMutexTimeoutMs }

        $logDirectory = Split-Path -Parent $LogPath

        if ($logDirectory -and -not (Test-Path -LiteralPath $logDirectory)) {
            try {
                $null = New-Item -ItemType Directory -Path $logDirectory -Force -ErrorAction Stop
            }
            catch {
                Write-Warning "Write-DJMLog: failed to create log directory '$logDirectory': $_"
                return
            }
        }

        $resolvedLogPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LogPath)

        # Rotation check
        if ($effectiveMaxSizeMB -gt 0 -and (Test-Path -LiteralPath $LogPath)) {
            $fileInfo = [System.IO.FileInfo]::new($resolvedLogPath)
            if (($fileInfo.Length / 1MB) -ge $effectiveMaxSizeMB) {
                $timestamp   = [datetime]::UtcNow.ToString('yyyyMMdd-HHmmss')
                $baseName    = [System.IO.Path]::GetFileNameWithoutExtension($resolvedLogPath)
                $extension   = [System.IO.Path]::GetExtension($resolvedLogPath)
                $directory   = [System.IO.Path]::GetDirectoryName($resolvedLogPath)
                $rotatedPath = [System.IO.Path]::Combine($directory, "${baseName}_${timestamp}${extension}")
                try {
                    [System.IO.File]::Move($resolvedLogPath, $rotatedPath)
                    Write-Verbose "Write-DJMLog: rotated log to '$rotatedPath'"
                }
                catch {
                    Write-Warning "Write-DJMLog: failed to rotate log file: $_"
                }
            }
        }
    }

    process {
        # Warn if ErrorObject supplied without Level ERROR — context will not be captured
        if ($ErrorObject -and $Level -ne 'ERROR') {
            Write-Warning "Write-DJMLog: -ErrorObject was supplied but -Level is '$Level', not 'ERROR'. Error context will not be captured. Set -Level ERROR to record error details."
        }

        $utcNow = [datetime]::UtcNow.ToString('o')

        $logEntry = [System.Collections.Generic.Dictionary[string, PSObject]]::new()
        $logEntry['UtcTimestamp']  = $utcNow
        $logEntry['Level']         = $Level.ToUpperInvariant()
        $logEntry['Message']       = $Message
        $logEntry['CorrelationId'] = $CorrelationId

        $metadataEntry = $null
        if ($Metadata -or ($ErrorObject -and $Level -eq 'ERROR')) {
            $metadataEntry = [System.Collections.Generic.Dictionary[string, PSObject]]::new()
        }

        if ($Metadata) {
            if ($Metadata -is [hashtable]) {
                $convertedMetadata = ConvertTo-DJMDictionary -Hashtable $Metadata
                foreach ($key in $convertedMetadata.Keys) { $metadataEntry[$key] = $convertedMetadata[$key] }
            }
            elseif ($Metadata -is [PSCustomObject]) {
                foreach ($property in $Metadata.PSObject.Properties) { $metadataEntry[$property.Name] = $property.Value }
            }
            else {
                $metadataEntry['RawValue'] = $Metadata
            }
        }

        if ($ErrorObject -and $Level -eq 'ERROR') {
            if (-not $metadataEntry) {
                $metadataEntry = [System.Collections.Generic.Dictionary[string, PSObject]]::new()
            }

            $errorEntry     = [System.Collections.Generic.Dictionary[string, PSObject]]::new()
            $invocationInfo = $ErrorObject.InvocationInfo

            $errorScriptName = $null
            $errorLineNumber  = $null
            $errorCommand    = $null
            $errorPosition   = $null
            $errorType       = $null
            $errorMessage    = $null

            if ($invocationInfo) {
                $errorScriptName = if ([string]::IsNullOrEmpty($invocationInfo.ScriptName)) { $null }
                                   else { $invocationInfo.ScriptName }

                $errorLineNumber = if ($invocationInfo.ScriptLineNumber -gt 0) { $invocationInfo.ScriptLineNumber }
                                   else { $null }

                $errorCommand = if ($invocationInfo.MyCommand) { $invocationInfo.MyCommand.Name }
                                else { $null }

                $errorPosition = if ([string]::IsNullOrEmpty($invocationInfo.PositionMessage)) { $null }
                                 else { ($invocationInfo.PositionMessage -split "\n")[0] }
            }

            if ($ErrorObject.Exception) {
                $errorMessage = if ([string]::IsNullOrEmpty($ErrorObject.Exception.Message)) { $null }
                                else { $ErrorObject.Exception.Message }

                $errorType = $ErrorObject.Exception.GetType().FullName
            }

            $errorEntry['ScriptName']      = $errorScriptName
            $errorEntry['LineNumber']      = $errorLineNumber
            $errorEntry['Command']         = $errorCommand
            $errorEntry['PositionMessage'] = $errorPosition
            $errorEntry['Type']            = $errorType
            $errorEntry['Message']         = $errorMessage

            $metadataEntry['Error'] = $errorEntry
        }

        if ($metadataEntry -and $metadataEntry.Count -gt 0) {
            $logEntry['Metadata'] = $metadataEntry
        }

        $logEntryJson  = $logEntry | ConvertTo-Json -Compress -Depth $Depth
        $logEntryLine  = $logEntryJson + [System.Environment]::NewLine
        $mutexAcquired = $false

        try {
            try {
                $mutexAcquired = $script:LogMutex.WaitOne($effectiveMutexTimeoutMs)
            }
            catch [System.Threading.AbandonedMutexException] {
                # Another thread crashed while holding the mutex.
                # .NET transfers ownership to this thread on the exception, so we
                # can proceed safely — the mutex is now ours.
                $mutexAcquired = $true
            }

            if ($mutexAcquired) {
                [System.IO.File]::AppendAllText($resolvedLogPath, $logEntryLine, [System.Text.Encoding]::UTF8)
            }
            else {
                Write-Warning "Write-DJMLog: mutex timeout after ${effectiveMutexTimeoutMs}ms — log entry discarded. Message: '$Message'"
            }
        }
        catch {
            Write-Warning "Write-DJMLog: failed to write log entry to '$LogPath': $_"
        }
        finally {
            if ($mutexAcquired) { $script:LogMutex.ReleaseMutex() }
        }

        if ($PassThru) {
            ConvertTo-DJMOrderedPSObject -Dictionary $logEntry
        }
    }
}
