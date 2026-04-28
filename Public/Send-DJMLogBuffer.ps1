function Send-DJMLogBuffer {
    <#
    .SYNOPSIS
    Back-compat wrapper. Forwards to Flush-DJMLog (v2.0 async writer ADR-019).

    .DESCRIPTION
    In v1.x, Send-DJMLogBuffer flushed the in-memory Log Analytics buffer to
    the configured DCR endpoint synchronously from the calling runspace.

    In v2.0, the Log Analytics buffer lives inside the dedicated writer
    runspace. Flush behaviour is delegated to Flush-DJMLog, which signals the
    writer to perform a flush via a sentinel entry on the channel and then
    blocks until the channel has drained.

    The -Force semantics map directly to Flush-DJMLog -Force.

    Migration guidance:
        - Existing scripts that called `Send-DJMLogBuffer` continue to work.
        - New scripts should use `Flush-DJMLog` directly to express intent.

    .PARAMETER Force
    Forwarded to Flush-DJMLog -Force. Bypasses the half-open transition.

    .EXAMPLE
    Send-DJMLogBuffer            # equivalent to Flush-DJMLog
    Send-DJMLogBuffer -Force     # equivalent to Flush-DJMLog -Force

    .NOTES
    Returns nothing for v1.x source compatibility (Flush-DJMLog returns [bool]).
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param ([switch]$Force)

    if (-not $script:LogAnalyticsEnabled) {
        Write-Warning 'Send-DJMLogBuffer: Log Analytics integration is not enabled.'
        return
    }
    if (-not $script:DcrEndpointUri -or -not $script:DcrImmutableId -or -not $script:DcrStreamName) {
        Write-Warning 'Send-DJMLogBuffer: DcrEndpointUri, DcrImmutableId, and DcrStreamName must all be configured.'
        return
    }

    [void](Flush-DJMLog -Force:$Force.IsPresent -TimeoutSec 30)
}
