function Wait-DJMLog {
    <#
    .SYNOPSIS
    Blocks until the async writer channel has drained, with a timeout.

    .DESCRIPTION
    Wait-DJMLog is identical to Flush-DJMLog with a mandatory positive timeout
    and no Log Analytics flush sentinel. Use it when you need to wait for
    pending writes to land on disk without forcing a Log Analytics POST.

    .PARAMETER TimeoutSec
    Maximum number of seconds to wait. Mandatory and must be > 0.

    .OUTPUTS
    [bool] $true if drained within the timeout, $false on timeout.

    .EXAMPLE
    # Wait up to 5 seconds for queued entries to land
    if (-not (Wait-DJMLog -TimeoutSec 5)) {
        Write-Warning 'Writer did not drain within 5s'
    }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$TimeoutSec
    )

    if (-not $script:WriterChannel) { return $true }
    Wait-DJMProcessed -TimeoutMs ([int]([Math]::Min($TimeoutSec * 1000, [int]::MaxValue)))
}
