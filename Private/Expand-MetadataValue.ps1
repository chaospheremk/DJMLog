# Private recursive helper. Walks a PSCustomObject tree and writes flattened
# key-value pairs into the target dictionary using underscore-joined key paths.
#
# Cycle detection: a HashSet keyed by reference identity tracks every
# PSCustomObject already visited on the current recursion stack. On re-entry,
# the value is replaced with the literal string '<cycle>' so circular graphs
# terminate. MaxDepth remains the second line of defence.
function Expand-MetadataValue {
    param (
        [string]$Prefix,
        [object]$Value,
        [System.Collections.Generic.Dictionary[string, PSObject]]$Target,
        [int]$MaxDepth = 10,
        [System.Collections.Generic.HashSet[object]]$Visited
    )

    if ($null -eq $Visited) {
        $Visited = [System.Collections.Generic.HashSet[object]]::new(
            [System.Collections.Generic.ReferenceEqualityComparer]::Instance
        )
    }

    if ($MaxDepth -le 0) {
        $Target[$Prefix] = $Value
        return
    }

    if ($null -ne $Value -and $Value -is [PSCustomObject] -and $Value.PSObject.Properties.Count -gt 0) {
        if (-not $Visited.Add($Value)) {
            $Target[$Prefix] = '<cycle>'
            return
        }
        try {
            foreach ($property in $Value.PSObject.Properties) {
                $childKey = "${Prefix}_$($property.Name)"
                Expand-MetadataValue -Prefix $childKey -Value $property.Value -Target $Target -MaxDepth ($MaxDepth - 1) -Visited $Visited
            }
        }
        finally {
            [void]$Visited.Remove($Value)
        }
    }
    else {
        $Target[$Prefix] = $Value
    }
}
