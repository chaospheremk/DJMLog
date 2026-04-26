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

    $state = 'Closed'
    if ($script:AutoFlushDisabled) {
        if ($script:AutoFlushOpenedAtUtc -and
            ([datetime]::UtcNow - $script:AutoFlushOpenedAtUtc).TotalSeconds -ge $script:HalfOpenAfterSeconds) {
            $state = 'HalfOpen-Probe-Pending'
        }
        else {
            $state = 'Open'
        }
    }

    [pscustomobject]@{
        Errors               = $script:InternalErrors.ToArray()
        CircuitBreakerState  = $state
        AutoFlushOpenedAtUtc = $script:AutoFlushOpenedAtUtc
    }
}
