function Start-DJMActivity {
    <#
    .SYNOPSIS
    Pushes a new activity scope onto the per-runspace activity stack.

    .DESCRIPTION
    Activities give Write-DJMLog a default CorrelationId, ParentActivityId, and
    ActivityName when those parameters are omitted. Activities nest: the new
    activity's ParentActivityId is the previous top-of-stack activity (if any).

    Stop-DJMActivity pops the most recently pushed activity and emits an
    INFO-level "activity finished" entry containing the elapsed duration.

    The activity stack is per-runspace ($script: scope). Nesting is tracked
    locally; entries pushed on the writer's channel carry the activity context
    snapshotted at write time.

    Activities also feed into the W3C Trace Context pickup: when
    [System.Diagnostics.Activity]::Current is non-null at write time,
    Write-DJMLog records its TraceId and SpanId under Metadata.Trace.

    .PARAMETER Name
    Required. Human-readable activity name (e.g. 'ProvisionUser').

    .PARAMETER CorrelationId
    Override the activity's correlation id. Defaults to a new GUID.

    .OUTPUTS
    [pscustomobject] - the activity frame { Id, ParentId, Name, StartUtc }.

    .EXAMPLE
    # Wrap a unit of work in an activity
    Start-DJMActivity -Name 'SyncTenantUsers'
    try {
        Write-DJMLog -Message 'Sync started'
        # ... work ...
        Write-DJMLog -Message 'Sync completed'
    }
    finally {
        Stop-DJMActivity
    }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [string]$CorrelationId
    )

    if ($null -eq $script:ActivityStack) {
        $script:ActivityStack = [System.Collections.Generic.Stack[pscustomobject]]::new()
    }

    $parentId = $null
    if ($script:ActivityStack.Count -gt 0) {
        $parentId = $script:ActivityStack.Peek().Id
    }

    if (-not $CorrelationId) { $CorrelationId = (New-Guid).Guid }

    $frame = [pscustomobject]@{
        Id            = (New-Guid).Guid
        ParentId      = $parentId
        Name          = $Name
        StartUtc      = [datetime]::UtcNow
        CorrelationId = $CorrelationId
    }
    $script:ActivityStack.Push($frame)
    $frame
}
