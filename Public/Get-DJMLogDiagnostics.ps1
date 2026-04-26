function Get-DJMLogDiagnostics {
    <#
    .SYNOPSIS
    Returns the module's internal error queue (SelfLog).

    .DESCRIPTION
    DJMLog deliberately avoids throwing terminating errors during log writes —
    a logging library that crashes its host is unacceptable. Instead, every
    catch block in Write-DJMLog, Send-DJMLogBuffer, Read-DJMLog, and
    Get-DJMBearerToken records the failure into a bounded in-memory queue
    (last 100 entries, FIFO eviction).

    Get-DJMLogDiagnostics returns a snapshot of that queue so callers can
    surface logging-pipeline failures (mutex timeouts, rotation errors,
    Log Analytics flush failures, token acquisition errors) at their own
    discretion. Newest entries are last.

    The queue is in-memory only and cleared on module reload.

    .OUTPUTS
    [pscustomobject[]] Each entry has fields:
        UtcTimestamp - ISO 8601 timestamp of the internal error
        Source       - Originating function (e.g. 'Write-DJMLog')
        Message      - Human-readable failure description
        Exception    - The original exception object, when available

    Note: the Exception field is the raw .NET exception. For Log Analytics
    failures it may embed infrastructure identifiers (tenant ID, DCE
    hostname, immutable ID). It does not contain credentials, but treat
    diagnostics output the same as any other infrastructure-config dump
    when sharing externally.

    .EXAMPLE
    # Inspect recent internal failures
    Get-DJMLogDiagnostics | Format-Table UtcTimestamp, Source, Message

    .EXAMPLE
    # Filter to flush failures only
    Get-DJMLogDiagnostics | Where-Object Source -eq 'Send-DJMLogBuffer'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Returns a collection of diagnostic entries; plural noun matches the contract.')]
    param ()

    $script:InternalErrors.ToArray()
}
