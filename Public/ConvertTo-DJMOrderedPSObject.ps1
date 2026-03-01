function ConvertTo-DJMOrderedPSObject {
    <#
    .SYNOPSIS
    Converts an IDictionary into a PSCustomObject with stable property order.

    .DESCRIPTION
    Iterates the source dictionary's keys in enumeration order, copies each
    key-value pair into an [ordered] hashtable, and casts the result to
    PSCustomObject. The property order of the returned object matches the
    key enumeration order of the input dictionary.

    Accepts any type implementing IDictionary, including Hashtable,
    OrderedDictionary, and Dictionary[string, PSObject].

    .PARAMETER Dictionary
    The source dictionary to convert.

    .OUTPUTS
    PSCustomObject

    .EXAMPLE
    # Convert a generic dictionary returned by ConvertTo-DJMDictionary
    $dict   = ConvertTo-DJMDictionary -Hashtable @{ Name = 'Prod'; Region = 'UKSouth' }
    $object = ConvertTo-DJMOrderedPSObject -Dictionary $dict
    $object | Format-List
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Dictionary
    )

    $orderedHashtable = [ordered]@{}
    foreach ($key in $Dictionary.Keys) {
        $orderedHashtable[$key] = $Dictionary[$key]
    }

    [PSCustomObject]$orderedHashtable
}
