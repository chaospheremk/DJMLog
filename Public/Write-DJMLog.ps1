function Write-DJMLog {
    <#
    .SYNOPSIS
    Submits a structured entry to the async writer for fan-out across the configured sinks.

    .DESCRIPTION
    v2.0 Write-DJMLog is the *producer* side of the async writer: it validates,
    enriches (host context, activity stack, W3C Trace Context), redacts, and
    pushes the entry onto a bounded channel. A dedicated writer runspace drains
    the channel and feeds each enabled sink (File / Console / EventLog /
    LogAnalytics).

    The Channel is BoundedChannel<hashtable> with FullMode = DropOldest. Drops
    are surfaced via Get-DJMLogDiagnostics.DroppedCount. Use Flush-DJMLog or
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
        Metadata            - free-form. Metadata.Trace { TraceId, SpanId } is
                              auto-populated when [Activity]::Current is non-null.
                              Metadata.Caller, Metadata.Error are populated as in v1.

    Min-level filtering and sampling apply BEFORE the channel write so suppressed
    entries don't consume channel capacity.

    Redaction:
        SecureString and PSCredential metadata values are unconditionally
        replaced with '[REDACTED]'. Keys matching (?i)password|secret|token|apikey
        are redacted. Configurable -RedactionPatterns / -RedactionPresets on
        Set-DJMLogConfig add string-level regex redaction.

    Activity scopes:
        When an activity is on the stack (Start-DJMActivity), its CorrelationId
        is used unless -CorrelationId was supplied explicitly.

    Breaking changes from v1:
        - Returns immediately after enqueue; the file write is asynchronous.
          For scripts that previously assumed synchronous on-disk durability,
          call Flush-DJMLog before relying on the file content.
        - Schema gains SchemaVersion / SeverityNumber / Host / ActivityId /
          ParentActivityId / ActivityName fields. Read-DJMLog auto-detects v1.

    .PARAMETER Message
    The human-readable log message.

    .PARAMETER Level
    Severity. INFO | WARN | ERROR | DEBUG | FATAL. Defaults to INFO.

    .PARAMETER CorrelationId
    Correlate related entries. Defaults to the active activity's CorrelationId,
    falling back to a fresh GUID.

    .PARAMETER LogPath
    Per-call file-sink override. When omitted, the module-level value from
    Set-DJMLogConfig is used.

    .PARAMETER Metadata
    Optional hashtable / PSCustomObject merged into the entry's Metadata block.

    .PARAMETER ErrorObject
    ErrorRecord; only valid when -Level ERROR or FATAL.

    .PARAMETER MinLevel
    Per-call minimum severity threshold.

    .PARAMETER NoCaller
    Suppress caller auto-capture for this call.

    .PARAMETER NoHostContext
    Suppress Host enrichment for this call.

    .PARAMETER PassThru
    Emit the entry to the pipeline as a PSCustomObject in addition to enqueueing.
    Note: redaction has already been applied to the returned object — values
    matching the always-on rules (SecureString / PSCredential / sensitive
    metadata keys) and any configured RedactionPatterns / RedactionPresets are
    `[REDACTED]` in the PassThru object.

    .OUTPUTS
    None by default. PSCustomObject when -PassThru is specified.

    .EXAMPLE
    Write-DJMLog -Message 'Sync started' -Level INFO

    .EXAMPLE
    try { ... } catch { Write-DJMLog -Message 'Failed' -Level ERROR -ErrorObject $_ }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory, ParameterSetName = 'Default')]
        [Parameter(Mandatory, ParameterSetName = 'Error')]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'Error')]
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG', 'FATAL', IgnoreCase = $true)]
        [string]$Level = 'INFO',

        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'Error')]
        [string]$CorrelationId,

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
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL', IgnoreCase = $true)]
        [string]$MinLevel,

        # Per-call file-sink overrides. These are forwarded to the writer as
        # sidecar fields on the entry; the File sink reads them with fallback
        # to the module defaults from Set-DJMLogConfig.
        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'Error')]
        [double]$MaxSizeMB = -1,

        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'Error')]
        [ValidateSet('None', 'Daily', 'Hourly', IgnoreCase = $true)]
        [string]$RotationSchedule,

        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'Error')]
        [int]$RetainDays = -1,

        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'Error')]
        [int]$RetainFiles = -1,

        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'Error')]
        [int]$MutexTimeoutMs = -2,

        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'Error')]
        [ValidateRange(1, 100)]
        [int]$Depth = 8,

        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'Error')]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$CallerDepth = 1,

        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'Error')]
        [switch]$NoCaller,

        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'Error')]
        [switch]$NoHostContext,

        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'Error')]
        [switch]$PassThru
    )

    process {
        # Level filter
        $effectiveMinLevel = if ($PSBoundParameters.ContainsKey('MinLevel')) { $MinLevel.ToUpperInvariant() } else { $script:DefaultMinLevel }
        $levelOrder = @{ DEBUG = 0; INFO = 1; WARN = 2; ERROR = 3; FATAL = 4 }
        $upperLevel = $Level.ToUpperInvariant()
        if ($levelOrder[$upperLevel] -lt $levelOrder[$effectiveMinLevel]) { return }

        # Sampling — applied after MinLevel, before channel write (per ADR-024)
        if ($script:SampleRate -is [hashtable] -and $script:SampleRate.ContainsKey($upperLevel)) {
            $rate = [double]$script:SampleRate[$upperLevel]
            if ($rate -le 0.0) { return }
            if ($rate -lt 1.0) {
                $r = [System.Random]::Shared.NextDouble()
                if ($r -gt $rate) { return }
            }
        }

        # When -ErrorObject is supplied alongside a non-ERROR/FATAL level, warn
        # the caller and continue without the error enrichment. Dropping the
        # entire entry (the v2.0 first-draft behaviour) silently masked the
        # caller's log message, which is worse than the missing error context.
        $captureError = $false
        if ($ErrorObject -and ($upperLevel -eq 'ERROR' -or $upperLevel -eq 'FATAL')) {
            $captureError = $true
        }
        elseif ($ErrorObject) {
            Write-Warning "Write-DJMLog: -ErrorObject was supplied but -Level is '$Level'. Error context not captured. Set -Level ERROR or FATAL to record error details."
        }

        # SeverityNumber per OTel spec: TRACE=1-4, DEBUG=5-8, INFO=9-12, WARN=13-16, ERROR=17-20, FATAL=21-24
        $severityNumber = switch ($upperLevel) {
            'DEBUG' { 5 } 'INFO' { 9 } 'WARN' { 13 } 'ERROR' { 17 } 'FATAL' { 21 } default { 9 }
        }

        $utcNow = [datetime]::UtcNow.ToString('o')

        $entry = [System.Collections.Generic.Dictionary[string, PSObject]]::new()
        $entry['SchemaVersion']  = $script:SchemaVersion
        $entry['UtcTimestamp']   = $utcNow
        $entry['Level']          = $upperLevel
        $entry['SeverityNumber'] = $severityNumber
        $entry['Message']        = $Message
        if ($PSBoundParameters.ContainsKey('CorrelationId') -and $CorrelationId) {
            $entry['CorrelationId'] = $CorrelationId
        }

        # Metadata block
        $metadataEntry = $null
        if ($Metadata -or $captureError) {
            $metadataEntry = [System.Collections.Generic.Dictionary[string, PSObject]]::new()
        }

        if ($Metadata) {
            if ($Metadata -is [hashtable]) {
                foreach ($k in $Metadata.Keys) { $metadataEntry[$k] = $Metadata[$k] }
            }
            elseif ($Metadata.GetType().FullName -eq 'System.Management.Automation.PSCustomObject') {
                foreach ($p in $Metadata.PSObject.Properties) { $metadataEntry[$p.Name] = $p.Value }
            }
            else {
                $metadataEntry['RawValue'] = $Metadata
            }
        }

        # Error capture
        if ($captureError) {
            if (-not $metadataEntry) { $metadataEntry = [System.Collections.Generic.Dictionary[string, PSObject]]::new() }
            $errorEntry = [System.Collections.Generic.Dictionary[string, PSObject]]::new()
            $invocationInfo = $ErrorObject.InvocationInfo

            $errorEntry['ScriptName']      = if ($invocationInfo -and -not [string]::IsNullOrEmpty($invocationInfo.ScriptName)) { $invocationInfo.ScriptName } else { $null }
            $errorEntry['LineNumber']      = if ($invocationInfo -and $invocationInfo.ScriptLineNumber -gt 0) { $invocationInfo.ScriptLineNumber } else { $null }
            $errorEntry['Command']         = if ($invocationInfo -and $invocationInfo.MyCommand) { $invocationInfo.MyCommand.Name } else { $null }
            $errorEntry['PositionMessage'] = if ($invocationInfo -and -not [string]::IsNullOrEmpty($invocationInfo.PositionMessage)) { ($invocationInfo.PositionMessage -split "\n")[0] } else { $null }
            $errorEntry['Type']            = if ($ErrorObject.Exception) { $ErrorObject.Exception.GetType().FullName } else { $null }
            $errorEntry['Message']         = if ($ErrorObject.Exception -and -not [string]::IsNullOrEmpty($ErrorObject.Exception.Message)) { $ErrorObject.Exception.Message } else { $null }

            $chain = [System.Collections.Generic.List[object]]::new()
            $visited = [System.Collections.Generic.HashSet[object]]::new(
                [System.Collections.Generic.ReferenceEqualityComparer]::Instance)
            $queue = [System.Collections.Generic.Queue[object]]::new()
            if ($ErrorObject.Exception) {
                [void]$visited.Add($ErrorObject.Exception)
                if ($ErrorObject.Exception -is [System.AggregateException]) {
                    foreach ($i in $ErrorObject.Exception.InnerExceptions) { if ($i) { $queue.Enqueue($i) } }
                }
                elseif ($ErrorObject.Exception.InnerException) { $queue.Enqueue($ErrorObject.Exception.InnerException) }
            }
            while ($queue.Count -gt 0) {
                $current = $queue.Dequeue()
                if (-not $current -or -not $visited.Add($current)) { continue }
                $entryDict = [System.Collections.Generic.Dictionary[string, PSObject]]::new()
                $entryDict['Type']    = $current.GetType().FullName
                $entryDict['Message'] = $current.Message
                $chain.Add($entryDict)
                if ($current -is [System.AggregateException]) {
                    foreach ($i in $current.InnerExceptions) { if ($i) { $queue.Enqueue($i) } }
                }
                elseif ($current.InnerException) { $queue.Enqueue($current.InnerException) }
            }
            if ($chain.Count -gt 0) { $errorEntry['ExceptionChain'] = $chain.ToArray() }

            $metadataEntry['Error'] = $errorEntry
        }

        # Caller capture
        if (-not $NoCaller -and $script:DefaultIncludeCaller -and -not $env:DJMLOG_CALLER_OFF) {
            $callStack = Get-PSCallStack
            if ($callStack.Count -gt $CallerDepth) {
                $callerFrame = $callStack[$CallerDepth]
                $callerEntry = [System.Collections.Generic.Dictionary[string, PSObject]]::new()
                $callerEntry['ScriptName']   = if ([string]::IsNullOrEmpty($callerFrame.ScriptName))   { $null } else { $callerFrame.ScriptName }
                $callerEntry['FunctionName'] = if ([string]::IsNullOrEmpty($callerFrame.FunctionName)) { $null } else { $callerFrame.FunctionName }
                $callerEntry['LineNumber']   = $callerFrame.ScriptLineNumber

                if ($null -eq $metadataEntry) { $metadataEntry = [System.Collections.Generic.Dictionary[string, PSObject]]::new() }
                if (-not $metadataEntry.ContainsKey('Caller')) { $metadataEntry['Caller'] = $callerEntry }
            }
        }

        if ($metadataEntry) { $entry['Metadata'] = $metadataEntry }

        # Enrichment (host + activity + W3C trace)
        $includeHost = -not $NoHostContext.IsPresent -and $script:DefaultIncludeHostContext
        Invoke-DJMEnrichment -Entry $entry -IncludeHostContext $includeHost -IncludeActivity $true -IncludeTrace $true

        # Ensure CorrelationId is set (activity may have provided it already)
        if (-not $entry.ContainsKey('CorrelationId') -or [string]::IsNullOrEmpty([string]$entry['CorrelationId'])) {
            $entry['CorrelationId'] = (New-Guid).Guid
        }

        # Redaction. Always-on rules (SecureString / PSCredential / sensitive
        # metadata key names) fire regardless of configured patterns/presets,
        # so this call is unconditional. Failures are swallowed so a regex
        # bug never blocks the log entry from reaching the channel.
        try { [void](Invoke-DJMRedaction -Value $entry) } catch { $null = $_ }

        # Push onto channel. Per-call file-sink overrides are carried as
        # sidecars; the File sink reads them with fallback to Shared defaults.
        if ($PSBoundParameters.ContainsKey('LogPath') -and $LogPath) {
            $entry['_LogPathOverride'] = $LogPath
        }
        if ($MaxSizeMB -ge 0)              { $entry['_MaxSizeMB']        = $MaxSizeMB }
        if ($PSBoundParameters.ContainsKey('RotationSchedule')) { $entry['_RotationSchedule'] = $RotationSchedule }
        if ($RetainDays -ge 0)             { $entry['_RetainDays']       = $RetainDays }
        if ($RetainFiles -ge 0)            { $entry['_RetainFiles']      = $RetainFiles }
        if ($MutexTimeoutMs -ne -2)        { $entry['_MutexTimeoutMs']   = $MutexTimeoutMs }

        # v1.x-compat LA buffer mirror — when sync mode is active, also push the
        # entry into $script:LogBuffer so existing tests asserting on
        # $script:LogBuffer.Count continue to work. The writer's own LABuffer
        # is still the canonical store for production flushes.
        if ($script:LogAnalyticsEnabled -and $env:DJMLOG_SYNC_WRITES) {
            $bufferEntry = @{
                UtcTimestamp  = $entry['UtcTimestamp']
                Level         = $entry['Level']
                Message       = $entry['Message']
                CorrelationId = $entry['CorrelationId']
            }
            if ($entry.ContainsKey('Metadata')) { $bufferEntry['Metadata'] = $entry['Metadata'] }

            $entryBytes = 0
            try {
                $entryJson  = $bufferEntry | ConvertTo-Json -Compress -Depth $Depth
                $entryBytes = [System.Text.Encoding]::UTF8.GetByteCount($entryJson)
            }
            catch { $entryBytes = 0 }

            $script:BufferLock.Wait()
            try {
                if ($script:LogBuffer.Count -ge $script:MaxBufferSize) {
                    $evicted = $script:LogBuffer[0]
                    $script:LogBuffer.RemoveAt(0)
                    $script:BufferByteTotal = [math]::Max(0, $script:BufferByteTotal - (Get-DJMEntryByteCount -Entry $evicted -Depth $Depth))
                    Add-DJMInternalError -Source 'Write-DJMLog' -Message "Log Analytics buffer full ($($script:MaxBufferSize)); oldest entry dropped"
                }
                if ($script:MaxBufferBytes -gt 0 -and $entryBytes -gt 0) {
                    while ($script:LogBuffer.Count -gt 0 -and
                           ($script:BufferByteTotal + $entryBytes) -gt $script:MaxBufferBytes) {
                        $evicted = $script:LogBuffer[0]
                        $script:LogBuffer.RemoveAt(0)
                        $script:BufferByteTotal = [math]::Max(0, $script:BufferByteTotal - (Get-DJMEntryByteCount -Entry $evicted -Depth $Depth))
                        Add-DJMInternalError -Source 'Write-DJMLog' -Message "Log Analytics buffer full (bytes); oldest entry dropped (MaxBufferBytes=$($script:MaxBufferBytes))"
                    }
                }
                $script:LogBuffer.Add($bufferEntry)
                $script:BufferByteTotal += $entryBytes
                if ($script:LogBuffer.Count -ge $script:FlushThreshold -and -not $script:AutoFlushDisabled) {
                    $shouldFlush = $true
                }
                else { $shouldFlush = $false }
            }
            finally { [void]$script:BufferLock.Release() }

            if ($shouldFlush) { Send-DJMLogBuffer }
        }

        $accepted = Push-DJMEntry -Entry $entry
        if (-not $accepted) {
            Write-Warning 'Write-DJMLog: writer channel rejected the entry.'
            Add-DJMInternalError -Source 'Write-DJMLog' -Message 'Writer channel rejected entry'
        }

        # Synchronous-write mode: when DJMLOG_SYNC_WRITES is set the writer
        # round-trips a fence per call so the file write is durable on return.
        # Used by the test suite for v1.x assertion compatibility.
        if ($accepted -and $env:DJMLOG_SYNC_WRITES) {
            [void](Wait-DJMProcessed -TimeoutMs 5000)
        }

        if ($PassThru -and $accepted) {
            $orderedHashtable = [ordered]@{}
            foreach ($key in $entry.Keys) { $orderedHashtable[$key] = $entry[$key] }
            [PSCustomObject]$orderedHashtable
        }
    }
}
