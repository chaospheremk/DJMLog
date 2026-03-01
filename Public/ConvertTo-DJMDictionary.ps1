function ConvertTo-DJMDictionary {
    <#
    .SYNOPSIS
    Converts PSObjects or a hashtable into a Dictionary[string, PSObject].

    .DESCRIPTION
    Accepts input via two mutually exclusive parameter sets:

      FromObjectList
          Each PSObject (piped or passed directly) is added to the dictionary
          using the value of the specified property as its key. Keys are
          trimmed and lowercased before insertion. Duplicate keys emit a
          non-terminating error and the second object is discarded.

      FromHashtable
          Each key-value pair in the hashtable is copied into the dictionary
          as-is, with no key transformation applied.

    .PARAMETER InputObject
    One or more PSObjects to index. Accepts pipeline input. Each object must
    have a property matching the name supplied to -KeyProperty.

    .PARAMETER KeyProperty
    The property name whose value is used as the dictionary key. The value
    is trimmed of whitespace and converted to lowercase before insertion.

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
    [OutputType([System.Collections.Generic.Dictionary[string, PSObject]])]
    param (
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'FromObjectList')]
        [PSObject]$InputObject,

        [Parameter(Mandatory, ParameterSetName = 'FromObjectList')]
        [string]$KeyProperty,

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
                try { $dictionary.Add($key, $InputObject) }
                catch { Write-Error -Message $_.Exception.Message }
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
