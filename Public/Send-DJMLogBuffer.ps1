function Send-DJMLogBuffer {
    <#
    .SYNOPSIS
    Flushes the in-memory log buffer to Azure Log Analytics via the Logs Ingestion API.

    .DESCRIPTION
    Sends buffered log entries to the configured Data Collection Rule (DCR) endpoint
    in chunked batches of up to 950 KB each (raw, pre-compression). Each record's
    UtcTimestamp is mapped to the TimeGenerated field so timestamps remain accurate
    regardless of when the batch is sent.

    Chunking uses incremental UTF-8 byte accounting: each record's encoded length is
    summed against a running batch size, and a new batch is started before the
    cumulative size would cross the 950 KB threshold. Records whose individual
    serialised size already exceeds 950 KB are rejected — they are removed from the
    buffer and a SelfLog entry is queued so callers can detect the drop via
    Get-DJMLogDiagnostics.

    Preconditions:
      - LogAnalyticsEnabled must be $true (via Set-DJMLogConfig)
      - DcrEndpointUri, DcrImmutableId, and DcrStreamName must be configured
      - The buffer must contain at least one entry
      - Auto-flush must not be disabled (circuit breaker) unless -Force is used,
        or the half-open window (HalfOpenAfterSeconds, default 300s) has elapsed

    Circuit breaker (per ADR-017):
      Closed   - normal operation. Failures up to MaxFlushRetries trip the breaker.
      Open     - auto-flush rejected; the call returns with a warning. -Force
                 overrides.
      HalfOpen - once HalfOpenAfterSeconds has elapsed since the breaker opened,
                 the next non-Force call attempts a single-shot probe (MaxRetries=1).
                 Success closes the breaker; failure refreshes the open timer.

    HTTP requests (token acquisition + DCR POST) route through the
    Invoke-DJMRestMethodWithRetry helper, which honours Retry-After on 429 and
    applies exponential backoff with jitter on 5xx (per ADR-016).

    Buffer access is serialised through an in-process SemaphoreSlim
    ($script:BufferLock) so concurrent Write-DJMLog and Send-DJMLogBuffer calls
    in the same process cannot corrupt the underlying List. Cross-process file
    writes are still serialised by the named OS mutex.

    .PARAMETER Force
    Bypasses the auto-flush circuit breaker. Use after investigating and resolving
    the underlying connectivity or configuration issue.

    .EXAMPLE
    # Manually flush the buffer
    Send-DJMLogBuffer

    .EXAMPLE
    # Force flush after circuit breaker tripped
    Send-DJMLogBuffer -Force
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [switch]$Force
    )

    # Precondition: LA must be enabled
    if (-not $script:LogAnalyticsEnabled) {
        Write-Warning 'Send-DJMLogBuffer: Log Analytics integration is not enabled. Use Set-DJMLogConfig -LogAnalyticsEnabled $true.'
        return
    }

    # Precondition: required config
    if (-not $script:DcrEndpointUri -or -not $script:DcrImmutableId -or -not $script:DcrStreamName) {
        Write-Warning 'Send-DJMLogBuffer: DcrEndpointUri, DcrImmutableId, and DcrStreamName must all be configured.'
        return
    }

    # Snapshot buffer count under the semaphore to avoid racing with Write-DJMLog
    $bufferEmpty = $false
    $script:BufferLock.Wait()
    try {
        $bufferEmpty = ($script:LogBuffer.Count -eq 0)
    }
    finally {
        [void]$script:BufferLock.Release()
    }
    if ($bufferEmpty) {
        Write-Verbose 'Send-DJMLogBuffer: buffer is empty, nothing to send.'
        return
    }

    # Circuit breaker: closed / open / half-open
    $isProbe = $false
    if ($script:AutoFlushDisabled -and -not $Force) {
        $halfOpenEligible = $false
        if ($script:AutoFlushOpenedAtUtc) {
            $elapsed = ([datetime]::UtcNow - $script:AutoFlushOpenedAtUtc).TotalSeconds
            if ($elapsed -ge $script:HalfOpenAfterSeconds) {
                $halfOpenEligible = $true
            }
        }
        if ($halfOpenEligible) {
            $isProbe = $true
        }
        else {
            Write-Warning "Send-DJMLogBuffer: auto-flush is disabled after $($script:MaxFlushRetries) consecutive failures. Use -Force to override or fix the underlying issue."
            return
        }
    }

    # Acquire bearer token
    $token = Get-DJMBearerToken
    if (-not $token) {
        Write-Warning 'Send-DJMLogBuffer: failed to acquire a bearer token. Buffer entries are preserved.'
        Add-DJMInternalError -Source 'Send-DJMLogBuffer' -Message 'Failed to acquire bearer token; buffer entries preserved'
        if ($isProbe) {
            $script:AutoFlushOpenedAtUtc = [datetime]::UtcNow
            return
        }
        $script:FlushFailureCount++
        if ($script:FlushFailureCount -ge $script:MaxFlushRetries) {
            $script:AutoFlushDisabled = $true
            if (-not $script:AutoFlushOpenedAtUtc) {
                $script:AutoFlushOpenedAtUtc = [datetime]::UtcNow
            }
            Write-Warning "Send-DJMLogBuffer: auto-flush disabled after $($script:MaxFlushRetries) consecutive failures."
        }
        return
    }

    # Snapshot the buffer under the semaphore so a concurrent Write-DJMLog cannot
    # mutate the source list while we copy it.
    $snapshot = $null
    $script:BufferLock.Wait()
    try {
        $snapshot = [System.Collections.Generic.List[hashtable]]::new($script:LogBuffer)
    }
    finally {
        [void]$script:BufferLock.Release()
    }

    # Map fields and build chunked batches with incremental UTF-8 byte accounting.
    # Records exceeding 950 KB on their own are rejected (and removed from the
    # live buffer so they don't poison subsequent flushes).
    $maxBatchBytes  = 950 * 1024
    $batches        = [System.Collections.Generic.List[System.Collections.Generic.List[hashtable]]]::new()
    $batchSources   = [System.Collections.Generic.List[System.Collections.Generic.List[hashtable]]]::new()
    $oversized     = [System.Collections.Generic.List[hashtable]]::new()
    $current       = [System.Collections.Generic.List[hashtable]]::new()
    $currentSrc    = [System.Collections.Generic.List[hashtable]]::new()
    $currentSize   = 2  # account for JSON array brackets []

    foreach ($entry in $snapshot) {
        $record = @{
            TimeGenerated = $entry['UtcTimestamp']
            Level         = $entry['Level']
            Message       = $entry['Message']
            CorrelationId = $entry['CorrelationId']
        }
        if ($entry.ContainsKey('Metadata') -and $null -ne $entry['Metadata']) {
            try {
                $record['Metadata'] = $entry['Metadata'] | ConvertTo-Json -Compress -Depth 5
            }
            catch {
                $record['Metadata'] = '<serialization error>'
                Write-Warning "Send-DJMLogBuffer: failed to serialize Metadata for entry: $_"
                Add-DJMInternalError -Source 'Send-DJMLogBuffer' -Message 'Metadata serialization failed' -Exception $_.Exception
            }
        }

        $recordJson = $record | ConvertTo-Json -Compress -Depth 5
        $recordSize = [System.Text.Encoding]::UTF8.GetByteCount($recordJson) + 1  # +1 for comma

        if ($recordSize -gt $maxBatchBytes) {
            Add-DJMInternalError -Source 'Send-DJMLogBuffer' -Message "Single record exceeds 950 KB after serialisation ($recordSize bytes); record dropped"
            Write-Warning "Send-DJMLogBuffer: single record exceeds 950 KB ($recordSize bytes) and was dropped."
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

    # Drop oversized entries from the live buffer so they don't get retried.
    if ($oversized.Count -gt 0) {
        $script:BufferLock.Wait()
        try {
            foreach ($bad in $oversized) {
                if ($script:LogBuffer.Remove($bad)) {
                    $script:BufferByteTotal = [math]::Max(0, $script:BufferByteTotal - (Get-DJMEntryByteCount -Entry $bad))
                }
            }
        }
        finally {
            [void]$script:BufferLock.Release()
        }
    }

    if ($batches.Count -eq 0) {
        # Nothing left to send (all records were oversized). Treat as a no-op
        # success so we don't trip the circuit breaker on bad-data alone.
        Write-Verbose 'Send-DJMLogBuffer: no eligible records after oversize filtering.'
        return
    }

    # On a half-open probe we only attempt the first batch with no retry. Either
    # the breaker closes (success) or the open timer is refreshed (failure).
    if ($isProbe -and $batches.Count -gt 1) {
        $batches      = [System.Collections.Generic.List[System.Collections.Generic.List[hashtable]]]::new(@($batches[0]))
        $batchSources = [System.Collections.Generic.List[System.Collections.Generic.List[hashtable]]]::new(@($batchSources[0]))
    }

    # POST each batch
    $uri = "$($script:DcrEndpointUri)/dataCollectionRules/$($script:DcrImmutableId)/streams/$($script:DcrStreamName)?api-version=2023-01-01"
    $headers = @{
        Authorization  = "Bearer $token"
    }

    $sentEntries = [System.Collections.Generic.List[hashtable]]::new()

    for ($i = 0; $i -lt $batches.Count; $i++) {
        $batch    = $batches[$i]
        $sources  = $batchSources[$i]
        $jsonBody = $batch | ConvertTo-Json -Depth 5 -AsArray
        try {
            $retryParams = @{
                Uri         = $uri
                Method      = 'POST'
                Headers     = $headers
                Body        = $jsonBody
                ContentType = 'application/json'
                MaxRetries  = if ($isProbe) { 1 } else { 5 }
            }
            Invoke-DJMRestMethodWithRetry @retryParams | Out-Null
            foreach ($src in $sources) { $sentEntries.Add($src) }
        }
        catch {
            Write-Warning "Send-DJMLogBuffer: batch POST failed: $_"
            Add-DJMInternalError -Source 'Send-DJMLogBuffer' -Message "Batch POST failed: $($_.Exception.Message)" -Exception $_.Exception
            if ($sentEntries.Count -gt 0) {
                Remove-DJMSentEntries -Snapshot $sentEntries -Count $sentEntries.Count
            }
            if ($isProbe) {
                $script:AutoFlushOpenedAtUtc = [datetime]::UtcNow
                return
            }
            $script:FlushFailureCount++
            if ($script:FlushFailureCount -ge $script:MaxFlushRetries) {
                $script:AutoFlushDisabled = $true
                if (-not $script:AutoFlushOpenedAtUtc) {
                    $script:AutoFlushOpenedAtUtc = [datetime]::UtcNow
                }
                Write-Warning "Send-DJMLogBuffer: auto-flush disabled after $($script:MaxFlushRetries) consecutive failures."
            }
            return
        }
    }

    # All batches succeeded — remove sent entries from the live buffer by reference,
    # not by index. A concurrent Write-DJMLog at MaxBufferSize may have evicted the
    # head entry during the HTTP POST, so the snapshot's [0..N-1] slice is no longer
    # guaranteed to align with the live buffer's [0..N-1].
    if ($sentEntries.Count -gt 0) {
        Remove-DJMSentEntries -Snapshot $sentEntries -Count $sentEntries.Count
    }
    $script:FlushFailureCount    = 0
    $script:AutoFlushDisabled    = $false
    $script:AutoFlushOpenedAtUtc = $null
    Write-Verbose "Send-DJMLogBuffer: successfully sent $($sentEntries.Count) entries."
}
