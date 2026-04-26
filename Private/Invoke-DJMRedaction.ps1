# Private helper. Walks a metadata structure and replaces sensitive values
# with the literal string '[REDACTED]'.
#
# Always-on rules:
#   - SecureString    -> '[REDACTED]'
#   - PSCredential    -> '[REDACTED]'
#   - Hashtable / dictionary keys matching (?i)(password|secret|token|apikey)
#     -> value replaced with '[REDACTED]'
#
# Configurable rules (Set-DJMLogConfig):
#   - $script:RedactionPatterns - regex array; matched against string values,
#     match group is replaced with '[REDACTED]'
#   - $script:RedactionPresets  - any of 'Email', 'BearerToken', 'CreditCard'
#     activates a built-in regex
function Invoke-DJMRedaction {
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(Mandatory)]
        $Value
    )

    # Compose the active pattern list once (presets + user-supplied patterns)
    $allPatterns = [System.Collections.Generic.List[string]]::new()
    if ($script:RedactionPatterns) {
        foreach ($p in $script:RedactionPatterns) { $allPatterns.Add($p) }
    }
    if ($script:RedactionPresets) {
        foreach ($preset in $script:RedactionPresets) {
            switch ($preset) {
                'Email'       { $allPatterns.Add('[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}') }
                'BearerToken' { $allPatterns.Add('(?i)bearer\s+[A-Za-z0-9._\-]+') }
                'CreditCard'  { $allPatterns.Add('\b(?:\d[ -]*?){13,19}\b') }
            }
        }
    }

    $visited = [System.Collections.Generic.HashSet[object]]::new(
        [System.Collections.Generic.ReferenceEqualityComparer]::Instance)

    Invoke-DJMRedactionWorker -Node $Value -KeyHint $null -Patterns $allPatterns -Visited $visited
}

# Recursive worker. Defined as a function so command lookup keeps working when
# called from inside a module (a previous draft used a GetNewClosure scriptblock
# which rebound out of the module session state and broke command resolution).
function Invoke-DJMRedactionWorker {
    [CmdletBinding()]
    [OutputType([object])]
    param (
        $Node,
        $KeyHint,
        [System.Collections.Generic.List[string]]$Patterns,
        [System.Collections.Generic.HashSet[object]]$Visited
    )

    if ($null -eq $Node) { return $null }

    if ($Node -is [System.Security.SecureString]) { return '[REDACTED]' }
    if ($Node -is [System.Management.Automation.PSCredential]) { return '[REDACTED]' }

    if ($KeyHint -and $KeyHint -match '(?i)password|secret|token|apikey') {
        if ($Node -is [string] -or $Node.GetType().IsPrimitive -or $Node -is [decimal]) {
            return '[REDACTED]'
        }
    }

    if ($Node -is [string]) {
        $current = $Node
        foreach ($pattern in $Patterns) {
            try { $current = [regex]::Replace($current, $pattern, '[REDACTED]') }
            catch { $null = $_ }
        }
        return $current
    }

    if ($Node -is [hashtable] -or $Node -is [System.Collections.IDictionary]) {
        if (-not $Visited.Add($Node)) { return $Node }
        try {
            $newKeys = New-Object 'System.Collections.Generic.List[object]'
            foreach ($k in @($Node.Keys)) { $newKeys.Add($k) }
            foreach ($k in $newKeys) {
                $Node[$k] = Invoke-DJMRedactionWorker -Node $Node[$k] -KeyHint $k -Patterns $Patterns -Visited $Visited
            }
        }
        finally { [void]$Visited.Remove($Node) }
        return $Node
    }

    if ($Node -is [System.Collections.IEnumerable] -and -not ($Node -is [string])) {
        if ($Node -is [System.Collections.IList]) {
            if (-not $Visited.Add($Node)) { return $Node }
            try {
                for ($i = 0; $i -lt $Node.Count; $i++) {
                    $Node[$i] = Invoke-DJMRedactionWorker -Node $Node[$i] -KeyHint $null -Patterns $Patterns -Visited $Visited
                }
            }
            finally { [void]$Visited.Remove($Node) }
            return $Node
        }
    }

    if ($Node -is [PSCustomObject]) {
        if (-not $Visited.Add($Node)) { return $Node }
        try {
            foreach ($p in $Node.PSObject.Properties) {
                if ($p.IsSettable) {
                    $p.Value = Invoke-DJMRedactionWorker -Node $p.Value -KeyHint $p.Name -Patterns $Patterns -Visited $Visited
                }
            }
        }
        finally { [void]$Visited.Remove($Node) }
        return $Node
    }

    $Node
}
