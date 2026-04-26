function ConvertTo-DJMDictionary {
    <#
    .SYNOPSIS
    Converts PSObjects or a hashtable into a Dictionary[string, PSObject].

    .DESCRIPTION
    Accepts input via two mutually exclusive parameter sets:

      FromObjectList
          Each PSObject (piped or passed directly) is added to the dictionary
          using the value of the specified property as its key. Keys are
          trimmed and lowercased before insertion. Behavior on duplicate keys
          is governed by -OnDuplicateKey (default: Overwrite).

      FromHashtable
          Each key-value pair in the hashtable is copied into the dictionary
          as-is, with no key transformation applied.

    .PARAMETER InputObject
    One or more PSObjects to index. Accepts pipeline input. Each object must
    have a property matching the name supplied to -KeyProperty.

    .PARAMETER KeyProperty
    The property name whose value is used as the dictionary key. The value
    is trimmed of whitespace and converted to lowercase before insertion.

    .PARAMETER OnDuplicateKey
    Controls duplicate-key behavior in the FromObjectList parameter set:
        Overwrite (default) - the later object wins; no error is emitted.
        Error               - the first object is kept; a non-terminating
                              error is emitted for each duplicate.
        KeepFirst           - the first object is kept; no error is emitted.

    .PARAMETER Hashtable
    A hashtable to convert. Keys are copied without transformation.

    .OUTPUTS
    System.Collections.Generic.Dictionary[string, PSObject]

    .EXAMPLE
    # Build a lookup from an AD query
    $userIndex = Get-ADUser -Filter * -Properties Department |
        ConvertTo-DJMDictionary -KeyProperty 'SamAccountName'
    $userIndex['jsmith'].Department

    .EXAMPLE
    # Convert a hashtable of config values
    $config = ConvertTo-DJMDictionary -Hashtable @{
        Environment = 'Production'
        Region      = 'UKSouth'
    }
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.IDictionary])]
    param (
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'FromObjectList')]
        [PSObject]$InputObject,

        [Parameter(Mandatory, ParameterSetName = 'FromObjectList')]
        [ValidateNotNullOrEmpty()]
        [string]$KeyProperty,

        [Parameter(ParameterSetName = 'FromObjectList')]
        [ValidateSet('Overwrite', 'Error', 'KeepFirst')]
        [string]$OnDuplicateKey = 'Overwrite',

        [Parameter(Mandatory, ParameterSetName = 'FromHashtable')]
        [hashtable]$Hashtable
    )

    begin {
        $dictionary = [System.Collections.Generic.Dictionary[string, PSObject]]::new()
    }

    process {
        switch ($PSCmdlet.ParameterSetName) {
            'FromObjectList' {
                $key = $InputObject.$KeyProperty.ToString().Trim().ToLowerInvariant()
                if ($dictionary.ContainsKey($key)) {
                    switch ($OnDuplicateKey) {
                        'Overwrite' { $dictionary[$key] = $InputObject }
                        'KeepFirst' { } # silently keep the first
                        'Error'     { Write-Error -Message "ConvertTo-DJMDictionary: duplicate key '$key' (existing entry preserved)." }
                    }
                }
                else {
                    $dictionary[$key] = $InputObject
                }
            }

            'FromHashtable' {
                foreach ($key in $Hashtable.Keys) {
                    $dictionary[$key] = $Hashtable[$key]
                }
            }
        }
    }

    end {
        $dictionary
    }
}
