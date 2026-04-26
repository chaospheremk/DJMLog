# Private helper. Returns the UTF-8 byte size of a buffer entry's JSON
# representation, or 0 if serialisation fails. Used by Write-DJMLog and
# Send-DJMLogBuffer to keep $script:BufferByteTotal accurate without
# O(N) recomputes.
function Get-DJMEntryByteCount {
    [CmdletBinding()]
    [OutputType([int])]
    param (
        [Parameter(Mandatory)]
        $Entry,

        [int]$Depth = 5
    )

    try {
        $json = $Entry | ConvertTo-Json -Compress -Depth $Depth
        [System.Text.Encoding]::UTF8.GetByteCount($json)
    }
    catch {
        0
    }
}
