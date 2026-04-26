function Send-DJMLogBuffer {
    <#
    .SYNOPSIS
    Flushes the in-memory log buffer to Azure Log Analytics via the Logs Ingestion API.

    .DESCRIPTION
    Sends buffered log entries to the configured Data Collection Rule (DCR) endpoint
    in chunked batches of up to 500 KB each. Each record's UtcTimestamp is mapped to
    the TimeGenerated field so timestamps remain accurate regardless of when the batch
    is sent.

    Preconditions:
      - LogAnalyticsEnabled must be $true (via Set-DJMLogConfig)
      - DcrEndpointUri, DcrImmutableId, and DcrStreamName must be configured
      - The buffer must contain at least one entry
      - Auto-flush must not be disabled (circuit breaker) unless -Force is used

    On success, sent entries are removed from the buffer, the failure count is reset,
    and auto-flush is re-enabled. On failure, the failure count is incremented and
    auto-flush is disabled when MaxFlushRetries is reached. The function breaks on the
    first batch failure so partially sent entries are removed while unsent entries
    remain buffered for the next attempt.

    Buffer access is serialised through an in-process SemaphoreSlim
    ($script:BufferLock) so concurrent Write-DJMLog and Send-DJMLogBuffer calls in
    the same process cannot corrupt the underlying List. Cross-process file writes
    are still serialised by the named OS mutex.

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

    # Precondition: circuit breaker (unless -Force)
    if ($script:AutoFlushDisabled -and -not $Force) {
        Write-Warning "Send-DJMLogBuffer: auto-flush is disabled after $($script:MaxFlushRetries) consecutive failures. Use -Force to override or fix the underlying issue."
        return
    }

    # Acquire bearer token
    $token = Get-DJMBearerToken
    if (-not $token) {
        Write-Warning 'Send-DJMLogBuffer: failed to acquire a bearer token. Buffer entries are preserved.'
        Add-DJMInternalError -Source 'Send-DJMLogBuffer' -Message 'Failed to acquire bearer token; buffer entries preserved'
        $script:FlushFailureCount++
        if ($script:FlushFailureCount -ge $script:MaxFlushRetries) {
            $script:AutoFlushDisabled = $true
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

    # Map fields: UtcTimestamp -> TimeGenerated, serialise Metadata as JSON string
    $mapped = [System.Collections.Generic.List[hashtable]]::new($snapshot.Count)
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
        $mapped.Add($record)
    }

    # Chunk into batches <= 500 KB
    $maxBatchBytes = 500 * 1024
    $batches   = [System.Collections.Generic.List[System.Collections.Generic.List[hashtable]]]::new()
    $current   = [System.Collections.Generic.List[hashtable]]::new()
    $currentSize = 2  # account for JSON array brackets []

    foreach ($record in $mapped) {
        $recordJson = $record | ConvertTo-Json -Compress -Depth 5
        $recordSize = [System.Text.Encoding]::UTF8.GetByteCount($recordJson) + 1  # +1 for comma

        if ($current.Count -gt 0 -and ($currentSize + $recordSize) -gt $maxBatchBytes) {
            $batches.Add($current)
            $current = [System.Collections.Generic.List[hashtable]]::new()
            $currentSize = 2
        }

        $current.Add($record)
        $currentSize += $recordSize
    }

    if ($current.Count -gt 0) {
        $batches.Add($current)
    }

    # POST each batch
    $uri = "$($script:DcrEndpointUri)/dataCollectionRules/$($script:DcrImmutableId)/streams/$($script:DcrStreamName)?api-version=2023-01-01"
    $headers = @{
        Authorization  = "Bearer $token"
        'Content-Type' = 'application/json'
    }

    $totalSent = 0
    foreach ($batch in $batches) {
        $jsonBody = $batch | ConvertTo-Json -Depth 5 -AsArray
        try {
            Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -Body $jsonBody -ErrorAction Stop
            $totalSent += $batch.Count
        }
        catch {
            Write-Warning "Send-DJMLogBuffer: batch POST failed: $_"
            Add-DJMInternalError -Source 'Send-DJMLogBuffer' -Message "Batch POST failed: $($_.Exception.Message)" -Exception $_.Exception
            if ($totalSent -gt 0) {
                Remove-DJMSentEntries -Snapshot $snapshot -Count $totalSent
            }
            $script:FlushFailureCount++
            if ($script:FlushFailureCount -ge $script:MaxFlushRetries) {
                $script:AutoFlushDisabled = $true
                Write-Warning "Send-DJMLogBuffer: auto-flush disabled after $($script:MaxFlushRetries) consecutive failures."
            }
            return
        }
    }

    # All batches succeeded — remove sent entries from the live buffer by reference,
    # not by index. A concurrent Write-DJMLog at MaxBufferSize may have evicted the
    # head entry during the HTTP POST, so the snapshot's [0..totalSent-1] slice is
    # no longer guaranteed to align with the live buffer's [0..totalSent-1].
    Remove-DJMSentEntries -Snapshot $snapshot -Count $totalSent
    $script:FlushFailureCount  = 0
    $script:AutoFlushDisabled  = $false
    Write-Verbose "Send-DJMLogBuffer: successfully sent $totalSent entries."
}
