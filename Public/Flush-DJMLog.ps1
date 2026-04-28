function Flush-DJMLog {
    <#
    .SYNOPSIS
    Drains the async writer channel and (if Log Analytics is enabled) flushes the in-memory buffer.

    .DESCRIPTION
    Blocks until every entry submitted before the call has been processed by the
    writer runspace. When Log Analytics is enabled, additionally signals the
    writer to flush its in-memory buffer to the configured DCR endpoint
    immediately (subject to circuit-breaker state).

    Use Flush-DJMLog before terminating an automation script so in-flight log
    entries reach disk and the configured remote sinks before the process exits.

    .PARAMETER TimeoutSec
    Maximum number of seconds to wait for the channel drain. Defaults to -1
    (wait indefinitely). Returns $true on success, $false on timeout.

    .PARAMETER Force
    When Log Analytics auto-flush is in the Open circuit-breaker state, -Force
    issues an explicit flush attempt regardless. The half-open transition is
    bypassed.

    .OUTPUTS
    [bool] $true if drained within the timeout, $false on timeout.

    .EXAMPLE
    # End-of-script drain
    try { ... } finally { [void](Flush-DJMLog) }

    .EXAMPLE
    # Force a Log Analytics flush after a known outage recovered
    Flush-DJMLog -Force

    .NOTES
    The verb 'Flush' is the de-facto standard term for draining a logging
    buffer (Serilog Flush, NLog Flush, Microsoft.Extensions.Logging Flush).
    PowerShell does not include it in the approved-verbs list; the cmdlet
    suppresses PSUseApprovedVerbs at the call site rather than rename to a
    less-discoverable approved verb such as Sync- or Submit-.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '',
        Justification = 'Flush is the established term for a logging-buffer drain (Serilog Flush, NLog Flush).')]
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [int]$TimeoutSec = -1,
        [switch]$Force
    )

    if (-not $script:WriterChannel) { return $true }

    # Signal Log Analytics flush via a sentinel entry so it's processed in
    # channel order — entries enqueued before this call drain first, then LA
    # flushes everything they added to the LA buffer.
    if ($script:LogAnalyticsEnabled) {
        $sentinel = @{ _FlushLA = [bool]$Force.IsPresent }
        [void]$script:WriterChannel.Writer.TryWrite($sentinel)
    }

    $timeoutMs = if ($TimeoutSec -lt 0) { -1 } else { [int]([Math]::Min($TimeoutSec * 1000, [int]::MaxValue)) }
    Wait-DJMProcessed -TimeoutMs $timeoutMs
}
