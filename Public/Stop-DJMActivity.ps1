function Stop-DJMActivity {
    <#
    .SYNOPSIS
    Pops the most recently pushed activity scope and emits a duration entry.

    .DESCRIPTION
    Pops the top of the per-runspace activity stack and writes an INFO entry of
    the form "Activity '<Name>' finished" with Metadata.Activity.DurationMs.

    Calling Stop-DJMActivity when the stack is empty emits a non-terminating
    warning and is otherwise a no-op.

    .OUTPUTS
    [pscustomobject] - the popped frame, augmented with EndUtc and DurationMs.

    .EXAMPLE
    Start-DJMActivity -Name 'WorkUnit'
    try { ... } finally { Stop-DJMActivity }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param ()

    if ($null -eq $script:ActivityStack -or $script:ActivityStack.Count -eq 0) {
        Write-Warning 'Stop-DJMActivity: activity stack is empty.'
        return
    }

    $frame = $script:ActivityStack.Pop()
    $endUtc = [datetime]::UtcNow
    $durationMs = [long](($endUtc - $frame.StartUtc).TotalMilliseconds)

    $finished = [pscustomobject]@{
        Id            = $frame.Id
        ParentId      = $frame.ParentId
        Name          = $frame.Name
        StartUtc      = $frame.StartUtc
        EndUtc        = $endUtc
        DurationMs    = $durationMs
        CorrelationId = $frame.CorrelationId
    }

    Write-DJMLog -Message "Activity '$($frame.Name)' finished" -Level INFO -CorrelationId $frame.CorrelationId -Metadata @{
        Activity = @{
            Id         = $frame.Id
            ParentId   = $frame.ParentId
            Name       = $frame.Name
            DurationMs = $durationMs
        }
    } -NoCaller

    $finished
}
