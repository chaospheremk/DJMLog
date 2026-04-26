# Private helper. Enqueues an internal error record into the SelfLog queue
# ($script:InternalErrors) with FIFO eviction at $script:InternalErrorsMaxSize.
# Surfaced to callers via Get-DJMLogDiagnostics.
function Add-DJMInternalError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Message,

        [object]$Exception
    )

    $entry = [pscustomobject]@{
        UtcTimestamp = [datetime]::UtcNow.ToString('o')
        Source       = $Source
        Message      = $Message
        Exception    = $Exception
    }

    $script:InternalErrors.Enqueue($entry)
    while ($script:InternalErrors.Count -gt $script:InternalErrorsMaxSize) {
        [void]$script:InternalErrors.Dequeue()
    }
}
