# Private helper. Spawns the dedicated writer runspace + System.Threading.Channels.Channel
# pair that backs the v2.0 async writer (per ADR-019).
#
# Design:
#   - Main runspace: validate -> enrich -> redact -> TryWrite(entry)
#   - Channel:       BoundedChannel<hashtable>, capacity = $script:ChannelCapacity,
#                    FullMode = DropOldest. Dropped entries are surfaced via the
#                    DroppedCount counter in the synchronised state hashtable.
#   - Writer:        single-thread loop in a dedicated runspace draining entries
#                    and fanning out to enabled sinks (File / Console / EventLog / LogAnalytics).
#
# Cross-runspace state is the named OS mutex (already shared) plus the channel
# (passed by reference via SessionStateProxy.SetVariable) plus a [hashtable]::Synchronized
# instance carrying live config + counters. Set-DJMLogConfig in the main runspace
# mutates the shared hashtable so the writer picks changes up on the next entry
# without a runspace restart.
function Start-DJMWriter {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'LogMutex',
        Justification = 'LogMutex is captured by Invoke-FileSink defined inside the writer scriptblock; PSSA cannot trace the closure.')]
    [CmdletBinding()]
    [OutputType([void])]
    param ()

    if ($script:WriterRunspace) { return }

    # Bounded channel with DropOldest. Dropped entries bump $script:WriterShared.DroppedCount,
    # surfaced via Get-DJMLogDiagnostics.
    $opts = [System.Threading.Channels.BoundedChannelOptions]::new($script:ChannelCapacity)
    $opts.FullMode      = [System.Threading.Channels.BoundedChannelFullMode]::DropOldest
    $opts.SingleReader  = $true
    $opts.SingleWriter  = $false

    # Channel uses object as the element type so both hashtable and
    # Dictionary[string,PSObject] entries can be enqueued without runtime cast
    # surprises. The dispatch code only relies on IDictionary semantics.
    $script:WriterChannel = [System.Threading.Channels.Channel]::CreateBounded[object]($opts)

    # CancellationTokenSource — passed to WaitToReadAsync so Stop-DJMWriter can
    # interrupt the writer synchronously without relying on Channel.TryComplete
    # (which doesn't unblock GetAwaiter().GetResult() reliably across runspaces).
    $script:WriterCts = [System.Threading.CancellationTokenSource]::new()

    # Synchronised state visible to both runspaces. Mutated only via Update-DJMWriterShared
    # (called from the main-runspace Set-DJMLogConfig) and the writer's own counters.
    $script:WriterShared = [hashtable]::Synchronized(@{
        # Counters
        EnqueuedCount        = [int64]0
        ProcessedCount       = [int64]0
        DroppedCount         = [int64]0
        # Lifecycle
        StopRequested        = $false
        # Fence map (Flush-DJMLog / Wait-DJMLog)
        Fences               = [System.Collections.Concurrent.ConcurrentDictionary[string, System.Threading.ManualResetEventSlim]]::new()
        # Writer-side error queue (analogue of $script:InternalErrors; merged
        # into the diagnostics output in Get-DJMLogDiagnostics).
        Errors               = [System.Collections.Concurrent.ConcurrentQueue[pscustomobject]]::new()
        ErrorsMaxSize        = 100
        # Sink configuration (mirrors $script:Sinks). Updated by Set-DJMLogConfig.
        Sinks                = @('File')
        # File sink config snapshot (path + rotation/retention)
        LogPath              = $null
        MaxSizeMB            = 0.0
        RotationSchedule     = 'None'
        RetainDays           = 0
        RetainFiles          = 0
        MutexTimeoutMs       = 2000
        # Console sink config
        ConsoleColors        = @{ FATAL = 'Magenta'; ERROR = 'Red'; WARN = 'Yellow'; INFO = 'Gray'; DEBUG = 'DarkGray' }
        # EventLog sink config
        EventLogSource       = 'DJMLog'
        EventLogName         = 'Application'
        EventLogSourceReady  = $false
        # LogAnalytics sink state
        LogAnalyticsEnabled  = $false
        LABuffer             = [System.Collections.Generic.List[hashtable]]::new()
        LABufferByteTotal    = [int64]0
        FlushThreshold       = 100
        MaxBufferSize        = 5000
        MaxBufferBytes       = [int64]52428800
        MaxFlushRetries      = 3
        FlushFailureCount    = 0
        AutoFlushDisabled    = $false
        AutoFlushOpenedAtUtc = $null
        HalfOpenAfterSeconds = 300
        # LogAnalytics endpoint config (snapshot updated by Set-DJMLogConfig)
        DcrEndpointUri       = $null
        DcrImmutableId       = $null
        DcrStreamName        = $null
        TenantId             = $null
        AppId                = $null
        AppSecret            = $null
        CertificateSubject   = $null
        CertificateThumbprint= $null
        BearerTokenExternal  = $null
        BearerTokenCache     = $null
        BearerTokenExpiry    = [datetime]::MinValue
        CloudEnvironment     = 'GCCHigh'
    })

    # Writer scriptblock. All sink logic lives inline — the runspace does not
    # re-import DJMLog (that would create a second module-state copy and the
    # cross-runspace coordination would be brittle). Helper sink functions are
    # defined here and read from $shared on every entry so a runtime
    # Set-DJMLogConfig propagates without a runspace restart.
    #
    # NOTE: param() must be the first statement; the retry helper is concatenated
    # *after* this preamble in the combined script (see below).
    $writerScript = {
        param ($Channel, $Shared, $LogMutex, $CancelToken)
        # __RETRY_HELPER_PLACEHOLDER__

        # Throttle EventLog source-registration retries when ACL denies it.
        $eventLogSourceAttempted = $false

        function Add-WriterErr {
            param ([string]$Source, [string]$Message, [object]$Exception)
            $Shared.Errors.Enqueue([pscustomobject]@{
                UtcTimestamp = [datetime]::UtcNow.ToString('o')
                Source       = $Source
                Message      = $Message
                Exception    = $Exception
            })
            while ($Shared.Errors.Count -gt $Shared.ErrorsMaxSize) {
                $discard = $null
                [void]$Shared.Errors.TryDequeue([ref]$discard)
            }
        }

        function Get-EntryByteCount {
            param ($Entry)
            try {
                $json = $Entry | ConvertTo-Json -Compress -Depth 8
                [System.Text.Encoding]::UTF8.GetByteCount($json)
            }
            catch { 0 }
        }

        function Invoke-FileSink {
            param ($Entry)

            $logPath          = if ($Entry.ContainsKey('_LogPathOverride'))    { $Entry['_LogPathOverride'] }    else { $Shared.LogPath }
            $maxSizeMB        = if ($Entry.ContainsKey('_MaxSizeMB'))          { [double]$Entry['_MaxSizeMB'] }   else { [double]$Shared.MaxSizeMB }
            $rotationSchedule = if ($Entry.ContainsKey('_RotationSchedule'))   { $Entry['_RotationSchedule'] }    else { $Shared.RotationSchedule }
            $retainDays       = if ($Entry.ContainsKey('_RetainDays'))         { [int]$Entry['_RetainDays'] }     else { [int]$Shared.RetainDays }
            $retainFiles      = if ($Entry.ContainsKey('_RetainFiles'))        { [int]$Entry['_RetainFiles'] }    else { [int]$Shared.RetainFiles }
            $mutexTimeoutMs   = if ($Entry.ContainsKey('_MutexTimeoutMs'))     { [int]$Entry['_MutexTimeoutMs'] } else { [int]$Shared.MutexTimeoutMs }
            if (-not $logPath) { return }
            # Strip sidecars before serialisation
            foreach ($k in '_LogPathOverride', '_MaxSizeMB', '_RotationSchedule', '_RetainDays', '_RetainFiles', '_MutexTimeoutMs') {
                if ($Entry.ContainsKey($k)) { [void]$Entry.Remove($k) }
            }

            $logDirectory = [System.IO.Path]::GetDirectoryName($logPath)
            if ($logDirectory -and -not [System.IO.Directory]::Exists($logDirectory)) {
                try { [void][System.IO.Directory]::CreateDirectory($logDirectory) }
                catch {
                    Add-WriterErr -Source 'Write-DJMLog' -Message "Failed to create log directory '$logDirectory'" -Exception $_.Exception
                    return
                }
            }

            $line = ($Entry | ConvertTo-Json -Compress -Depth 8) + "`n"
            $mutexAcquired = $false
            $rotated       = $false
            try {
                try { $mutexAcquired = $LogMutex.WaitOne($mutexTimeoutMs) }
                catch [System.Threading.AbandonedMutexException] { $mutexAcquired = $true }

                if (-not $mutexAcquired) {
                    Add-WriterErr -Source 'Write-DJMLog' -Message "Mutex timeout after ${mutexTimeoutMs}ms; entry dropped"
                    return
                }

                # Rotation decision happens INSIDE the mutex (per BUG-009)
                if ([System.IO.File]::Exists($logPath)) {
                    try {
                        $fi = [System.IO.FileInfo]::new($logPath)
                        $fi.Refresh()
                        $shouldRotate = $false
                        if ($maxSizeMB -gt 0 -and ($fi.Length / 1MB) -ge $maxSizeMB) {
                            $shouldRotate = $true
                        }
                        if (-not $shouldRotate -and $rotationSchedule -and $rotationSchedule -ne 'None') {
                            if ($rotationSchedule -eq 'Daily') {
                                $shouldRotate = $fi.CreationTimeUtc.Date -lt [datetime]::UtcNow.Date
                            }
                            elseif ($rotationSchedule -eq 'Hourly') {
                                $hourStart = [datetime]::UtcNow.Date.AddHours([datetime]::UtcNow.Hour)
                                $shouldRotate = $fi.CreationTimeUtc -lt $hourStart
                            }
                        }

                        if ($shouldRotate) {
                            $timestamp = [datetime]::UtcNow.ToString('yyyyMMdd-HHmmss')
                            $baseName  = [System.IO.Path]::GetFileNameWithoutExtension($logPath)
                            $extension = [System.IO.Path]::GetExtension($logPath)
                            $directory = [System.IO.Path]::GetDirectoryName($logPath)
                            $rotatedPath = [System.IO.Path]::Combine($directory, "${baseName}_${timestamp}${extension}")
                            try {
                                [System.IO.File]::Move($logPath, $rotatedPath)
                                $rotated = $true
                            }
                            catch {
                                Add-WriterErr -Source 'Write-DJMLog' -Message "Rotation failed" -Exception $_.Exception
                            }
                        }
                    }
                    catch {
                        Add-WriterErr -Source 'Write-DJMLog' -Message "Rotation check failed" -Exception $_.Exception
                    }
                }

                # Append
                try {
                    [System.IO.File]::AppendAllText($logPath, $line, [System.Text.Encoding]::UTF8)
                }
                catch {
                    Add-WriterErr -Source 'Write-DJMLog' -Message "Append failed for '$logPath'" -Exception $_.Exception
                    # Fallback to stderr so the failure surfaces
                    try { [Console]::Error.WriteLine("DJMLog: file write failed: $($_.Exception.Message)") } catch { $null = $_ }
                    return
                }

                # Retention cleanup runs after a successful rotation
                if ($rotated -and ($retainDays -gt 0 -or $retainFiles -gt 0)) {
                    $baseName  = [System.IO.Path]::GetFileNameWithoutExtension($logPath)
                    $extension = [System.IO.Path]::GetExtension($logPath)
                    $directory = [System.IO.Path]::GetDirectoryName($logPath)
                    $cleanupPattern = "${baseName}_????????-??????${extension}"

                    try { $rotatedFiles = @([System.IO.Directory]::GetFiles($directory, $cleanupPattern)) }
                    catch {
                        Add-WriterErr -Source 'Write-DJMLog' -Message "Failed to enumerate rotated files for retention" -Exception $_.Exception
                        $rotatedFiles = @()
                    }

                    if ($retainDays -gt 0 -and $rotatedFiles.Count -gt 0) {
                        $cutoff = [datetime]::UtcNow.AddDays(-$retainDays)
                        foreach ($f in $rotatedFiles) {
                            try {
                                $fi = [System.IO.FileInfo]::new($f)
                                $fi.Refresh()
                                if ($fi.CreationTimeUtc -lt $cutoff) {
                                    [System.IO.File]::Delete($f)
                                }
                            }
                            catch {
                                Add-WriterErr -Source 'Write-DJMLog' -Message "Failed to delete '$f' during RetainDays cleanup" -Exception $_.Exception
                            }
                        }
                        try { $rotatedFiles = @([System.IO.Directory]::GetFiles($directory, $cleanupPattern)) }
                        catch {
                            Add-WriterErr -Source 'Write-DJMLog' -Message "Failed to re-enumerate rotated files" -Exception $_.Exception
                            $rotatedFiles = @()
                        }
                    }

                    if ($retainFiles -gt 0 -and $rotatedFiles.Count -gt $retainFiles) {
                        [System.Array]::Sort($rotatedFiles)
                        $deleteCount = $rotatedFiles.Count - $retainFiles
                        if ($deleteCount -gt 0) {
                            foreach ($f in $rotatedFiles[0..($deleteCount - 1)]) {
                                try { [System.IO.File]::Delete($f) }
                                catch {
                                    Add-WriterErr -Source 'Write-DJMLog' -Message "Failed to delete '$f' during RetainFiles cleanup" -Exception $_.Exception
                                }
                            }
                        }
                    }
                }
            }
            finally {
                if ($mutexAcquired) { try { $LogMutex.ReleaseMutex() } catch { $null = $_ } }
            }
        }

        function Invoke-ConsoleSink {
            param ($Entry)
            $level = [string]$Entry.Level
            $color = $Shared.ConsoleColors[$level]
            # Validate against the ConsoleColor enum so a misspelled value
            # (e.g. 'grey' vs 'Gray') doesn't render as Black/invisible.
            if (-not $color -or -not [System.Enum]::IsDefined([System.ConsoleColor], $color)) {
                $color = 'Gray'
            }
            $abbr = switch ($level) {
                'FATAL' { 'FTL' } 'ERROR' { 'ERR' } 'WARN' { 'WRN' }
                'INFO'  { 'INF' } 'DEBUG' { 'DBG' } default { '???' }
            }
            $ts  = $null
            try { $ts = [datetime]$Entry.UtcTimestamp } catch { $ts = [datetime]::UtcNow }
            $local = $ts.ToLocalTime()
            $msg = "$($local.ToString('yyyy-MM-dd HH:mm:ss')) [$abbr] $($Entry.Message)"
            # Always restore the colour even if WriteLine throws (e.g. ObjectDisposed
            # on host shutdown). Without this the console can be left in a
            # foreground-changed state permanently.
            $colorChanged = $false
            try {
                [Console]::ForegroundColor = [System.ConsoleColor]::$color
                $colorChanged = $true
                [Console]::WriteLine($msg)
            }
            catch { $null = $_ }
            finally {
                if ($colorChanged) {
                    try { [Console]::ResetColor() } catch { $null = $_ }
                }
            }
        }

        function Invoke-EventLogSink {
            param ($Entry)
            if (-not $IsWindows) { return }
            $entryType = switch ($Entry.Level) {
                'FATAL' { 'Error' } 'ERROR' { 'Error' } 'WARN' { 'Warning' } default { 'Information' }
            }
            try {
                if (-not $Shared.EventLogSourceReady -and -not $eventLogSourceAttempted) {
                    $eventLogSourceAttempted = $true
                    try {
                        if (-not [System.Diagnostics.EventLog]::SourceExists($Shared.EventLogSource)) {
                            [System.Diagnostics.EventLog]::CreateEventSource($Shared.EventLogSource, $Shared.EventLogName)
                        }
                        $Shared.EventLogSourceReady = $true
                    }
                    catch {
                        Add-WriterErr -Source 'EventLogSink' -Message "Failed to register event source '$($Shared.EventLogSource)'" -Exception $_.Exception
                        return
                    }
                }
                if ($Shared.EventLogSourceReady) {
                    $msg = "$($Entry.Level) $($Entry.Message) [cid:$($Entry.CorrelationId)]"
                    [System.Diagnostics.EventLog]::WriteEntry($Shared.EventLogSource, $msg, [System.Diagnostics.EventLogEntryType]::$entryType)
                }
            }
            catch {
                Add-WriterErr -Source 'EventLogSink' -Message "WriteEntry failed" -Exception $_.Exception
            }
        }

        function Invoke-LogAnalyticsSink {
            param ($Entry)
            if (-not $Shared.LogAnalyticsEnabled) { return }

            $bufferEntry = @{
                UtcTimestamp  = $Entry.UtcTimestamp
                Level         = $Entry.Level
                Message       = $Entry.Message
                CorrelationId = $Entry.CorrelationId
            }
            if ($Entry.ContainsKey('Metadata') -and $Entry.Metadata) { $bufferEntry['Metadata'] = $Entry.Metadata }

            $entryBytes = Get-EntryByteCount $bufferEntry

            $buf = $Shared.LABuffer
            # Drop-head if at count cap
            if ($buf.Count -ge $Shared.MaxBufferSize) {
                $evicted = $buf[0]
                $buf.RemoveAt(0)
                $Shared.LABufferByteTotal = [math]::Max(0, $Shared.LABufferByteTotal - (Get-EntryByteCount $evicted))
                Add-WriterErr -Source 'LogAnalyticsSink' -Message "LA buffer full (count=$($Shared.MaxBufferSize)); oldest entry dropped"
            }
            # Drop-head while over byte cap
            if ($Shared.MaxBufferBytes -gt 0 -and $entryBytes -gt 0) {
                while ($buf.Count -gt 0 -and ($Shared.LABufferByteTotal + $entryBytes) -gt $Shared.MaxBufferBytes) {
                    $evicted = $buf[0]
                    $buf.RemoveAt(0)
                    $Shared.LABufferByteTotal = [math]::Max(0, $Shared.LABufferByteTotal - (Get-EntryByteCount $evicted))
                    Add-WriterErr -Source 'LogAnalyticsSink' -Message "LA buffer full (bytes); oldest entry dropped"
                }
            }
            $buf.Add($bufferEntry)
            $Shared.LABufferByteTotal += $entryBytes

            if ($buf.Count -ge $Shared.FlushThreshold -and -not $Shared.AutoFlushDisabled) {
                Invoke-LogAnalyticsFlush
            }
        }

        function Invoke-LogAnalyticsFlush {
            param ([switch]$Force)
            if (-not $Shared.LogAnalyticsEnabled) { return }
            if ($Shared.LABuffer.Count -eq 0) { return }
            if (-not $Shared.DcrEndpointUri -or -not $Shared.DcrImmutableId -or -not $Shared.DcrStreamName) { return }

            # Half-open / open gating
            $isProbe = $false
            if ($Shared.AutoFlushDisabled -and -not $Force) {
                $halfOpenEligible = $false
                if ($Shared.AutoFlushOpenedAtUtc) {
                    $elapsed = ([datetime]::UtcNow - $Shared.AutoFlushOpenedAtUtc).TotalSeconds
                    if ($elapsed -ge $Shared.HalfOpenAfterSeconds) { $halfOpenEligible = $true }
                }
                if ($halfOpenEligible) { $isProbe = $true } else { return }
            }

            # Acquire token via writer-side helper
            $token = Get-LAToken
            if (-not $token) {
                Add-WriterErr -Source 'LogAnalyticsSink' -Message 'Failed to acquire bearer token; buffer preserved'
                if ($isProbe) { $Shared.AutoFlushOpenedAtUtc = [datetime]::UtcNow; return }
                $Shared.FlushFailureCount++
                if ($Shared.FlushFailureCount -ge $Shared.MaxFlushRetries) {
                    $Shared.AutoFlushDisabled = $true
                    if (-not $Shared.AutoFlushOpenedAtUtc) { $Shared.AutoFlushOpenedAtUtc = [datetime]::UtcNow }
                }
                return
            }

            # Snapshot the buffer
            $snapshot = [System.Collections.Generic.List[hashtable]]::new($Shared.LABuffer)

            # Build chunked batches with incremental UTF-8 byte accounting
            $maxBatchBytes = 950 * 1024
            $batches       = [System.Collections.Generic.List[System.Collections.Generic.List[hashtable]]]::new()
            $batchSources  = [System.Collections.Generic.List[System.Collections.Generic.List[hashtable]]]::new()
            $oversized     = [System.Collections.Generic.List[hashtable]]::new()
            $current       = [System.Collections.Generic.List[hashtable]]::new()
            $currentSrc    = [System.Collections.Generic.List[hashtable]]::new()
            $currentSize   = 2

            foreach ($entry in $snapshot) {
                $record = @{
                    TimeGenerated = $entry['UtcTimestamp']
                    Level         = $entry['Level']
                    Message       = $entry['Message']
                    CorrelationId = $entry['CorrelationId']
                }
                if ($entry.ContainsKey('Metadata') -and $null -ne $entry['Metadata']) {
                    try { $record['Metadata'] = $entry['Metadata'] | ConvertTo-Json -Compress -Depth 5 }
                    catch { $record['Metadata'] = '<serialization error>' }
                }

                $recordJson = $record | ConvertTo-Json -Compress -Depth 5
                $recordSize = [System.Text.Encoding]::UTF8.GetByteCount($recordJson) + 1

                if ($recordSize -gt $maxBatchBytes) {
                    Add-WriterErr -Source 'LogAnalyticsSink' -Message "Single record exceeds 950 KB ($recordSize bytes); record dropped"
                    $oversized.Add($entry)
                    continue
                }
                if ($current.Count -gt 0 -and ($currentSize + $recordSize) -gt $maxBatchBytes) {
                    $batches.Add($current)
                    $batchSources.Add($currentSrc)
                    $current     = [System.Collections.Generic.List[hashtable]]::new()
                    $currentSrc  = [System.Collections.Generic.List[hashtable]]::new()
                    $currentSize = 2
                }
                $current.Add($record)
                $currentSrc.Add($entry)
                $currentSize += $recordSize
            }
            if ($current.Count -gt 0) {
                $batches.Add($current)
                $batchSources.Add($currentSrc)
            }

            # Drop oversized records from live buffer
            if ($oversized.Count -gt 0) {
                foreach ($bad in $oversized) {
                    if ($Shared.LABuffer.Remove($bad)) {
                        $Shared.LABufferByteTotal = [math]::Max(0, $Shared.LABufferByteTotal - (Get-EntryByteCount $bad))
                    }
                }
            }

            if ($batches.Count -eq 0) { return }

            # On a probe, only attempt the first batch
            if ($isProbe -and $batches.Count -gt 1) {
                $batches      = [System.Collections.Generic.List[System.Collections.Generic.List[hashtable]]]::new(@($batches[0]))
                $batchSources = [System.Collections.Generic.List[System.Collections.Generic.List[hashtable]]]::new(@($batchSources[0]))
            }

            $uri = "$($Shared.DcrEndpointUri)/dataCollectionRules/$($Shared.DcrImmutableId)/streams/$($Shared.DcrStreamName)?api-version=2023-01-01"
            $sentEntries = [System.Collections.Generic.List[hashtable]]::new()

            for ($i = 0; $i -lt $batches.Count; $i++) {
                $batch    = $batches[$i]
                $sources  = $batchSources[$i]
                $jsonBody = $batch | ConvertTo-Json -Depth 5 -AsArray

                # gzip-compress the body and POST with Content-Encoding: gzip
                $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)
                $gzipBytes = $null
                try {
                    $ms = [System.IO.MemoryStream]::new()
                    try {
                        $gz = [System.IO.Compression.GZipStream]::new($ms, [System.IO.Compression.CompressionLevel]::Fastest, $true)
                        try { $gz.Write($bodyBytes, 0, $bodyBytes.Length) } finally { $gz.Dispose() }
                        $gzipBytes = $ms.ToArray()
                    }
                    finally { $ms.Dispose() }
                }
                catch {
                    Add-WriterErr -Source 'LogAnalyticsSink' -Message 'gzip encoding failed; sending uncompressed' -Exception $_.Exception
                    $gzipBytes = $null
                }

                try {
                    $headers = @{ Authorization = "Bearer $token" }
                    $params = @{
                        Uri         = $uri
                        Method      = 'POST'
                        Headers     = $headers
                        ContentType = 'application/json'
                        MaxRetries  = if ($isProbe) { 1 } else { 5 }
                    }
                    if ($gzipBytes) {
                        $headers['Content-Encoding'] = 'gzip'
                        $params['Body']    = $gzipBytes
                        $params['Headers'] = $headers
                    }
                    else {
                        $params['Body'] = $jsonBody
                    }
                    Invoke-DJMRestMethodWithRetry @params | Out-Null
                    foreach ($src in $sources) { $sentEntries.Add($src) }
                }
                catch {
                    Add-WriterErr -Source 'LogAnalyticsSink' -Message "Batch POST failed: $($_.Exception.Message)" -Exception $_.Exception
                    if ($sentEntries.Count -gt 0) {
                        foreach ($src in $sentEntries) {
                            if ($Shared.LABuffer.Remove($src)) {
                                $Shared.LABufferByteTotal = [math]::Max(0, $Shared.LABufferByteTotal - (Get-EntryByteCount $src))
                            }
                        }
                    }
                    if ($isProbe) { $Shared.AutoFlushOpenedAtUtc = [datetime]::UtcNow; return }
                    $Shared.FlushFailureCount++
                    if ($Shared.FlushFailureCount -ge $Shared.MaxFlushRetries) {
                        $Shared.AutoFlushDisabled = $true
                        if (-not $Shared.AutoFlushOpenedAtUtc) { $Shared.AutoFlushOpenedAtUtc = [datetime]::UtcNow }
                    }
                    return
                }
            }

            # Success — remove sent by reference
            if ($sentEntries.Count -gt 0) {
                foreach ($src in $sentEntries) {
                    if ($Shared.LABuffer.Remove($src)) {
                        $Shared.LABufferByteTotal = [math]::Max(0, $Shared.LABufferByteTotal - (Get-EntryByteCount $src))
                    }
                }
            }
            $Shared.FlushFailureCount    = 0
            $Shared.AutoFlushDisabled    = $false
            $Shared.AutoFlushOpenedAtUtc = $null
        }

        function Get-LAToken {
            # External token: short-circuit
            if ($Shared.BearerTokenExternal) { return $Shared.BearerTokenExternal }
            # Cache (5-min safety margin already baked into expiry)
            if ($Shared.BearerTokenCache -and [datetime]::UtcNow -lt $Shared.BearerTokenExpiry) {
                return $Shared.BearerTokenCache
            }
            if (-not $Shared.TenantId -or -not $Shared.AppId) {
                Add-WriterErr -Source 'LogAnalyticsSink' -Message 'TenantId/AppId missing for token acquisition'
                return $null
            }
            $cloudMap = @{
                Commercial = @{ LoginHost = 'login.microsoftonline.com'; Scope = 'https://monitor.azure.com//.default' }
                GCCHigh    = @{ LoginHost = 'login.microsoftonline.us';  Scope = 'https://monitor.azure.us//.default' }
                DoD        = @{ LoginHost = 'login.microsoftonline.us';  Scope = 'https://monitor.azure.us//.default' }
            }
            $endpoints = $cloudMap[$Shared.CloudEnvironment]
            if (-not $endpoints) { return $null }
            $tokenUrl = "https://$($endpoints.LoginHost)/$($Shared.TenantId)/oauth2/v2.0/token"

            # Build request body. We only support client_secret on the writer side
            # for simplicity; certificate JWT remains in the main runspace's
            # Get-DJMBearerToken (callable by main-runspace flush path).
            $body = $null
            if ($Shared.AppSecret) {
                $secretStr = $null
                try {
                    if ($Shared.AppSecret -is [System.Security.SecureString]) {
                        $netCred = [System.Net.NetworkCredential]::new('', $Shared.AppSecret)
                        $secretStr = $netCred.Password
                    }
                    else { $secretStr = [string]$Shared.AppSecret }
                    $body = @{
                        grant_type    = 'client_credentials'
                        client_id     = $Shared.AppId
                        client_secret = $secretStr
                        scope         = $endpoints.Scope
                    }
                }
                catch { return $null }
            }
            elseif ($Shared.CertificateThumbprint -or $Shared.CertificateSubject) {
                # Cert auth lives in the main runspace's Get-DJMBearerToken;
                # the writer cannot reach Cert: drive reliably across runspace
                # boundaries. Surface as SelfLog so user knows to flush via
                # the main runspace's Send-DJMLogBuffer / Flush-DJMLog path.
                Add-WriterErr -Source 'LogAnalyticsSink' -Message 'Certificate auth requires main-runspace Send-DJMLogBuffer / Flush-DJMLog; writer-side flush skipped'
                return $null
            }
            else { return $null }

            try {
                $resp = Invoke-DJMRestMethodWithRetry -Uri $tokenUrl -Method 'POST' -Body $body -ContentType 'application/x-www-form-urlencoded' -MaxRetries 5
                if (-not $resp.access_token -or -not $resp.expires_in) { return $null }
                $Shared.BearerTokenCache  = $resp.access_token
                $Shared.BearerTokenExpiry = [datetime]::UtcNow.AddSeconds($resp.expires_in - 300)
                return $Shared.BearerTokenCache
            }
            catch {
                Add-WriterErr -Source 'LogAnalyticsSink' -Message "Token acquisition failed: $($_.Exception.Message)" -Exception $_.Exception
                return $null
            }
        }

        # Main loop
        $reader     = $Channel.Reader
        $cancelTok  = $CancelToken
        while (-not $Shared.StopRequested) {
            $waitTask = $reader.WaitToReadAsync($cancelTok)
            try { $available = $waitTask.AsTask().GetAwaiter().GetResult() }
            catch { break }
            if (-not $available) { break }

            $entry = $null
            while ($reader.TryRead([ref]$entry)) {
                try {
                    if ($entry.ContainsKey('_Fence')) {
                        $fenceId = [string]$entry['_Fence']
                        $mre = $null
                        if ($Shared.Fences.TryGetValue($fenceId, [ref]$mre)) { $mre.Set() }
                    }
                    elseif ($entry.ContainsKey('_FlushLA')) {
                        $force = [bool]$entry['_FlushLA']
                        if ($force) { Invoke-LogAnalyticsFlush -Force }
                        else        { Invoke-LogAnalyticsFlush }
                    }
                    else {
                        $sinks = $Shared.Sinks
                        foreach ($sink in $sinks) {
                            switch ($sink) {
                                'File'         { Invoke-FileSink         -Entry $entry }
                                'Console'      { Invoke-ConsoleSink      -Entry $entry }
                                'EventLog'     { Invoke-EventLogSink     -Entry $entry }
                                'LogAnalytics' { Invoke-LogAnalyticsSink -Entry $entry }
                            }
                        }
                    }
                }
                catch {
                    Add-WriterErr -Source 'Writer' -Message "Dispatch failure: $($_.Exception.Message)" -Exception $_.Exception
                }
                finally {
                    [System.Threading.Monitor]::Enter($Shared.SyncRoot)
                    try { $Shared.ProcessedCount = [int64]$Shared.ProcessedCount + 1 }
                    finally { [System.Threading.Monitor]::Exit($Shared.SyncRoot) }
                }
            }
        }
    }

    # Build the runspace. We dot-source the retry helper into the writer's
    # session by reading its source file and injecting it via AddScript before
    # the writer loop. This avoids re-importing the whole module (which would
    # spawn a second writer; even with the env-var guard, the dual-state would
    # complicate cross-runspace coordination).
    $script:WriterRunspace = [runspacefactory]::CreateRunspace()
    $script:WriterRunspace.ApartmentState = [System.Threading.ApartmentState]::MTA
    $script:WriterRunspace.Open()

    $retryFnPath = Join-Path $PSScriptRoot 'Invoke-DJMRestMethodWithRetry.ps1'
    $retryFnBody = if (Test-Path -LiteralPath $retryFnPath) { Get-Content -LiteralPath $retryFnPath -Raw } else { '' }

    # Inject the retry helper into the writer scriptblock at the placeholder
    # position so the function is defined immediately after param(). This keeps
    # param() as the first statement (a parser requirement) while making the
    # helper visible inside the same scope as the writer loop.
    $writerSource = $writerScript.ToString().Replace('# __RETRY_HELPER_PLACEHOLDER__', $retryFnBody)
    $combined     = [scriptblock]::Create($writerSource)

    $script:WriterPS          = [powershell]::Create()
    $script:WriterPS.Runspace = $script:WriterRunspace
    [void]$script:WriterPS.AddScript($combined.ToString())
    [void]$script:WriterPS.AddArgument($script:WriterChannel)
    [void]$script:WriterPS.AddArgument($script:WriterShared)
    [void]$script:WriterPS.AddArgument($script:LogMutex)
    [void]$script:WriterPS.AddArgument($script:WriterCts.Token)
    $script:WriterAsyncResult = $script:WriterPS.BeginInvoke()
}

# Synchronise writer-relevant config from main-runspace state to $script:WriterShared.
# Called by Set-DJMLogConfig after any field that affects sinks / buffer / endpoint.
function Update-DJMWriterShared {
    [CmdletBinding()]
    [OutputType([void])]
    param ()

    if (-not $script:WriterShared) { return }

    $s = $script:WriterShared
    $s.LogPath              = $script:DefaultLogPath
    $s.MaxSizeMB            = [double]$script:DefaultMaxSizeMB
    $s.RotationSchedule     = $script:DefaultRotationSchedule
    $s.RetainDays           = [int]$script:DefaultRetainDays
    $s.RetainFiles          = [int]$script:DefaultRetainFiles
    $s.MutexTimeoutMs       = [int]$script:DefaultMutexTimeoutMs

    if ($null -ne $script:Sinks) { $s.Sinks = $script:Sinks }

    $s.LogAnalyticsEnabled  = [bool]$script:LogAnalyticsEnabled
    $s.FlushThreshold       = [int]$script:FlushThreshold
    $s.MaxBufferSize        = [int]$script:MaxBufferSize
    $s.MaxBufferBytes       = [int64]$script:MaxBufferBytes
    $s.MaxFlushRetries      = [int]$script:MaxFlushRetries
    $s.HalfOpenAfterSeconds = [int]$script:HalfOpenAfterSeconds
    $s.DcrEndpointUri       = $script:DcrEndpointUri
    $s.DcrImmutableId       = $script:DcrImmutableId
    $s.DcrStreamName        = $script:DcrStreamName
    $s.TenantId             = $script:TenantId
    $s.AppId                = $script:AppId
    $s.AppSecret            = $script:AppSecret
    $s.CertificateSubject   = $script:CertificateSubject
    $s.CertificateThumbprint= $script:CertificateThumbprint
    $s.BearerTokenExternal  = $script:BearerTokenExternal
    $s.CloudEnvironment     = $script:CloudEnvironment
}

# Block until ProcessedCount catches up to EnqueuedCount as observed at the moment
# of the call (or to the supplied snapshot). Used by Flush-DJMLog / Wait-DJMLog.
function Wait-DJMProcessed {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [int]$TimeoutMs = -1
    )

    if (-not $script:WriterShared) { return $true }

    # Push a fence sentinel and wait on its event. ProcessedCount alone is racy
    # because new writes may arrive during the wait; the fence model gives an
    # exact "all entries enqueued before this call are processed" semantic.
    $fenceId = [guid]::NewGuid().ToString()
    $mre     = [System.Threading.ManualResetEventSlim]::new($false)
    [void]$script:WriterShared.Fences.TryAdd($fenceId, $mre)
    try {
        $fence = @{ _Fence = $fenceId }
        if (-not $script:WriterChannel.Writer.TryWrite($fence)) { return $false }
        if ($TimeoutMs -lt 0) {
            # ManualResetEventSlim.Wait() with no args returns void; the bool
            # overloads only exist for the timeout/cancel forms. Wait
            # unconditionally then return $true so callers get a meaningful
            # [bool] result on the indefinite-wait path.
            $mre.Wait()
            return $true
        }
        return $mre.Wait($TimeoutMs)
    }
    finally {
        $removed = $null
        [void]$script:WriterShared.Fences.TryRemove($fenceId, [ref]$removed)
        try { $mre.Dispose() } catch { $null = $_ }
    }
}

# Stop the writer cleanly. Idempotent. Falls back to PowerShell.Stop()
# if the loop doesn't exit within $TimeoutMs.
function Stop-DJMWriter {
    [CmdletBinding()]
    [OutputType([void])]
    param ([int]$TimeoutMs = 2000)

    if (-not $script:WriterRunspace) { return }
    try {
        if ($script:WriterShared) { $script:WriterShared.StopRequested = $true }
        # Cancel the writer's WaitToReadAsync. This is the reliable wake-up
        # path; TryComplete + WaitOne deadlocked because GetAwaiter().GetResult()
        # owned the runspace thread and PowerShell.Stop couldn't preempt it.
        try { if ($script:WriterCts) { $script:WriterCts.Cancel() } } catch { $null = $_ }
        try { if ($script:WriterChannel) { [void]$script:WriterChannel.Writer.TryComplete() } } catch { $null = $_ }

        if ($script:WriterAsyncResult -and $script:WriterPS) {
            $stopped = $script:WriterAsyncResult.AsyncWaitHandle.WaitOne($TimeoutMs)
            if (-not $stopped) {
                try { $script:WriterPS.Stop() } catch { $null = $_ }
                try { [void]$script:WriterAsyncResult.AsyncWaitHandle.WaitOne(500) } catch { $null = $_ }
            }
            try { $null = $script:WriterPS.EndInvoke($script:WriterAsyncResult) } catch { $null = $_ }
        }
    }
    finally {
        try { if ($script:WriterPS) { $script:WriterPS.Dispose() } } catch { $null = $_ }
        try { if ($script:WriterRunspace) { $script:WriterRunspace.Dispose() } } catch { $null = $_ }
        try { if ($script:WriterCts) { $script:WriterCts.Dispose() } } catch { $null = $_ }
        $script:WriterPS          = $null
        $script:WriterRunspace    = $null
        $script:WriterAsyncResult = $null
        $script:WriterChannel     = $null
        $script:WriterShared      = $null
        $script:WriterCts         = $null
    }
}

# Push an entry onto the channel. Returns $true on success (might still be dropped
# by DropOldest later); $false only if the channel is closed or cannot accept a write.
function Push-DJMEntry {
    [CmdletBinding()]
    [OutputType([bool])]
    param ([Parameter(Mandatory)] $Entry)

    if (-not $script:WriterChannel) { return $false }

    # Capacity-pre-check: when the channel is at capacity we know a DropOldest
    # is about to happen. Bump the dropped counter so Get-DJMLogDiagnostics surfaces
    # it. This is best-effort — TryWrite never returns the dropped item.
    try {
        $writer = $script:WriterChannel.Writer
        if (-not $writer.TryWrite($Entry)) { return $false }
        $shared = $script:WriterShared
        [System.Threading.Monitor]::Enter($shared.SyncRoot)
        try {
            $shared.EnqueuedCount = [int64]$shared.EnqueuedCount + 1
            # Detect drop: if Enqueued - Processed > Capacity, a drop has happened.
            $diff = $shared.EnqueuedCount - $shared.ProcessedCount
            if ($diff -gt $script:ChannelCapacity) {
                $shared.DroppedCount = $diff - $script:ChannelCapacity
            }
        }
        finally { [System.Threading.Monitor]::Exit($shared.SyncRoot) }
        return $true
    }
    catch { return $false }
}
