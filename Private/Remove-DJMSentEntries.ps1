# Private helper. Removes the first $Count entries of the snapshot from
# $script:LogBuffer by reference (List<T>.Remove), not by index.
#
# Reference removal is correct in the presence of concurrent MaxBufferSize
# evictions: if Write-DJMLog evicted buffer[0] during the HTTP POST, the
# successfully-sent snapshot entries are still present in the buffer (they
# were copied into the snapshot before the eviction) at later indices.
# Index-based RemoveRange would have removed the wrong entries; reference
# removal removes the right ones regardless of where they slid to.
#
# If a snapshot entry is no longer present in the buffer (because it was
# itself evicted by MaxBufferSize before we got back here), Remove silently
# returns $false. That's the correct behaviour — the entry is already gone.
function Remove-DJMSentEntries {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Removes a batch of entries; plural noun matches the contract.')]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [System.Collections.Generic.List[hashtable]]$Snapshot,

        [Parameter(Mandatory)]
        [int]$Count
    )

    if ($Count -le 0) { return }

    $script:BufferLock.Wait()
    try {
        for ($i = 0; $i -lt $Count; $i++) {
            $entry = $Snapshot[$i]
            if ($script:LogBuffer.Remove($entry)) {
                $script:BufferByteTotal = [math]::Max(0, $script:BufferByteTotal - (Get-DJMEntryByteCount -Entry $entry))
            }
        }
    }
    finally {
        [void]$script:BufferLock.Release()
    }
}
