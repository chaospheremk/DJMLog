# Private helper. Last-resort sink when the primary file write fails.
# Tries the Windows Application Event Log first (source 'DJMLog', registered
# lazily with best-effort error handling); if that fails or the platform is
# non-Windows, writes to stderr via [Console]::Error.
#
# Never throws — fallback failures are silently swallowed so the caller's
# original error is preserved.
function Write-DJMFallback {
    param (
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('Information', 'Warning', 'Error')]
        [string]$EntryType = 'Error'
    )

    $writtenToEventLog = $false

    if ($IsWindows) {
        try {
            if (-not [System.Diagnostics.EventLog]::SourceExists('DJMLog')) {
                [System.Diagnostics.EventLog]::CreateEventSource('DJMLog', 'Application')
            }
            [System.Diagnostics.EventLog]::WriteEntry('DJMLog', $Message, [System.Diagnostics.EventLogEntryType]::$EntryType)
            $writtenToEventLog = $true
        }
        catch {
            $writtenToEventLog = $false
        }
    }

    if (-not $writtenToEventLog) {
        try {
            [Console]::Error.WriteLine("DJMLog [$EntryType] $Message")
        }
        catch {
            # Last-resort sink already failed; deliberately swallow so the
            # caller's original error is preserved. There is nowhere else to
            # report this from inside the fallback path itself.
            $null = $_
        }
    }
}
