# Private helper. Adds Schema-v2 enrichment to a log entry hashtable in-place:
#   - Host              { MachineName, ProcessId, UserName, PSVersion } when
#                       $script:DefaultIncludeHostContext is $true (default)
#   - Activity context  ActivityId, ParentActivityId, ActivityName from the
#                       per-runspace activity stack
#   - W3C trace context Metadata.Trace { TraceId, SpanId } when
#                       [System.Diagnostics.Activity]::Current is non-null
function Invoke-DJMEnrichment {
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory)]
        [System.Collections.Generic.Dictionary[string, PSObject]]$Entry,

        [bool]$IncludeHostContext = $true,

        [bool]$IncludeActivity    = $true,

        [bool]$IncludeTrace       = $true
    )

    if ($IncludeHostContext) {
        $hostInfo = [System.Collections.Generic.Dictionary[string, PSObject]]::new()
        $hostInfo['MachineName'] = [System.Environment]::MachineName
        $hostInfo['ProcessId']   = [System.Environment]::ProcessId
        $hostInfo['UserName']    = [System.Environment]::UserName
        $hostInfo['PSVersion']   = $PSVersionTable.PSVersion.ToString()
        $Entry['Host'] = $hostInfo
    }

    if ($IncludeActivity -and $script:ActivityStack -and $script:ActivityStack.Count -gt 0) {
        $top = $script:ActivityStack.Peek()
        $Entry['ActivityId']        = $top.Id
        $Entry['ParentActivityId']  = $top.ParentId
        $Entry['ActivityName']      = $top.Name
        # Override CorrelationId if caller didn't supply one explicitly. The
        # caller layer (Write-DJMLog) decides whether to use this — Invoke-DJMEnrichment
        # always sets it; Write-DJMLog only overrides when the user accepted the
        # default.
        if (-not $Entry.ContainsKey('CorrelationId') -or [string]::IsNullOrEmpty($Entry['CorrelationId'])) {
            $Entry['CorrelationId'] = $top.CorrelationId
        }
    }

    if ($IncludeTrace) {
        try {
            $current = [System.Diagnostics.Activity]::Current
            if ($current) {
                $traceId = $current.TraceId.ToString()
                $spanId  = $current.SpanId.ToString()
                if ($traceId -and $traceId -ne '00000000000000000000000000000000') {
                    $metadata = $null
                    if ($Entry.ContainsKey('Metadata')) { $metadata = $Entry['Metadata'] }
                    if ($null -eq $metadata) {
                        $metadata = [System.Collections.Generic.Dictionary[string, PSObject]]::new()
                        $Entry['Metadata'] = $metadata
                    }
                    $trace = [System.Collections.Generic.Dictionary[string, PSObject]]::new()
                    $trace['TraceId'] = $traceId
                    $trace['SpanId']  = $spanId
                    $metadata['Trace'] = $trace
                }
            }
        }
        catch { $null = $_ }
    }
}
