# Private recursive helper. Walks a PSCustomObject tree and writes flattened
# key-value pairs into the target dictionary using underscore-joined key paths.
function Expand-MetadataValue {
    param (
        [string]$Prefix,
        [object]$Value,
        [System.Collections.Generic.Dictionary[string, PSObject]]$Target,
        [int]$MaxDepth = 10
    )

    if ($MaxDepth -le 0) {
        $Target[$Prefix] = $Value
        return
    }

    if ($null -ne $Value -and $Value -is [PSCustomObject] -and $Value.PSObject.Properties.Count -gt 0) {
        foreach ($property in $Value.PSObject.Properties) {
            $childKey = "${Prefix}_$($property.Name)"
            Expand-MetadataValue -Prefix $childKey -Value $property.Value -Target $Target -MaxDepth ($MaxDepth - 1)
        }
    }
    else {
        $Target[$Prefix] = $Value
    }
}
