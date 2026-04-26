function Get-DJMLogDiagnostics {
    <#
    .SYNOPSIS
    Returns the module's internal error queue (SelfLog) plus circuit breaker state.

    .DESCRIPTION
    DJMLog deliberately avoids throwing terminating errors during log writes —
    a logging library that crashes its host is unacceptable. Instead, every
    catch block in Write-DJMLog, Send-DJMLogBuffer, Read-DJMLog, and
    Get-DJMBearerToken records the failure into a bounded in-memory queue
    (last 100 entries, FIFO eviction).

    Get-DJMLogDiagnostics returns a snapshot of that queue together with the
    Log Analytics circuit breaker state so callers can surface logging-pipeline
    failures (mutex timeouts, rotation errors, Log Analytics flush failures,
    token acquisition errors) at their own discretion. Newest entries are last.

    The queue is in-memory only and cleared on module reload.

    .OUTPUTS
    [pscustomobject] with fields:
        Errors               - Array of internal error entries
                               (UtcTimestamp, Source, Message, Exception)
        CircuitBreakerState  - 'Closed', 'Open', or 'HalfOpen-Probe-Pending'
        AutoFlushOpenedAtUtc - DateTime the circuit breaker opened, or $null

    Note: the Exception field on each error entry is the raw .NET exception.
    For Log Analytics failures it may embed infrastructure identifiers
    (tenant ID, DCE hostname, immutable ID). It does not contain credentials,
    but treat diagnostics output the same as any other infrastructure-config
    dump when sharing externally.

    .EXAMPLE
    # Inspect recent internal failures
    $diag = Get-DJMLogDiagnostics
    $diag.Errors | Format-Table UtcTimestamp, Source, Message

    .EXAMPLE
    # Check circuit breaker state in long-running automation
    if ((Get-DJMLogDiagnostics).CircuitBreakerState -ne 'Closed') {
        # alert / page
    }

    .NOTES
    Breaking change in v1.2: this cmdlet now returns a single PSCustomObject
    instead of an array of error records. v1.1 callers must migrate from
    `Get-DJMLogDiagnostics | ...` to `(Get-DJMLogDiagnostics).Errors | ...`.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Returns aggregate diagnostics; plural noun matches the contract.')]
    param ()

    # Compute breaker state as the union of main + writer state. Either side may
    # have flipped the breaker (main-runspace tests / Set-DJMLogConfig vs the
    # writer's LA flush path). Open wins over Closed; HalfOpen is the
    # "Open + window elapsed" derived state.
    $mainOpen    = [bool]$script:AutoFlushDisabled
    $mainOpenedAt = $script:AutoFlushOpenedAtUtc

    $writerOpen   = $false
    $writerOpenedAt = $null
    $enqueued    = 0L
    $processed   = 0L
    $dropped     = 0L
    $writerErrors = @()
    if ($script:WriterShared) {
        $writerOpen     = [bool]$script:WriterShared.AutoFlushDisabled
        $writerOpenedAt = $script:WriterShared.AutoFlushOpenedAtUtc
        $enqueued       = [int64]$script:WriterShared.EnqueuedCount
        $processed      = [int64]$script:WriterShared.ProcessedCount
        $dropped        = [int64]$script:WriterShared.DroppedCount
        $writerErrors   = @($script:WriterShared.Errors.ToArray())
    }

    $isOpen     = $mainOpen -or $writerOpen
    # Earliest non-null OpenedAt
    $autoOpened = if ($mainOpenedAt -and $writerOpenedAt) {
        if ($mainOpenedAt -lt $writerOpenedAt) { $mainOpenedAt } else { $writerOpenedAt }
    } elseif ($mainOpenedAt)   { $mainOpenedAt }
    elseif ($writerOpenedAt)   { $writerOpenedAt }
    else                       { $null }

    if ($isOpen) {
        if ($autoOpened -and ([datetime]::UtcNow - $autoOpened).TotalSeconds -ge $script:HalfOpenAfterSeconds) {
            $state = 'HalfOpen-Probe-Pending'
        }
        else {
            $state = 'Open'
        }
    }
    else {
        $state = 'Closed'
    }

    # Merge main + writer error queues; main first, writer second
    $allErrors = @($script:InternalErrors.ToArray()) + $writerErrors

    [pscustomobject]@{
        Errors               = $allErrors
        CircuitBreakerState  = $state
        AutoFlushOpenedAtUtc = $autoOpened
        EnqueuedCount        = $enqueued
        ProcessedCount       = $processed
        DroppedCount         = $dropped
        QueuedCount          = [Math]::Max(0L, $enqueued - $processed)
    }
}
