function Resolve-DJMCertificate {
    <#
    .SYNOPSIS
    Resolves an X.509 certificate from the local stores using thumbprint or subject.

    .DESCRIPTION
    Internal helper. Searches Cert:\LocalMachine\My then Cert:\CurrentUser\My for
    a certificate matching the supplied -Thumbprint or -Subject. Applies the
    DJMLog usability predicate:
      - NotAfter > UtcNow
      - HasPrivateKey
      - PublicKey.Key.KeySize >= MinKeySize (default 2048)

    Returns the candidate with the latest NotAfter when more than one matches,
    or $null when none qualify. Used by Get-DJMBearerToken (main runspace) and
    Update-DJMWriterShared (to marshal the resolved X509Certificate2 instance
    into the writer runspace, which cannot reach the Cert: PSDrive).

    .PARAMETER Thumbprint
    Certificate thumbprint. Searched directly via Get-Item on each store.

    .PARAMETER Subject
    Certificate subject (e.g. 'CN=DJMLog-Auth'). Each store is enumerated and
    every certificate whose Subject matches exactly is considered.

    .PARAMETER MinKeySize
    Minimum acceptable RSA key size in bits. Defaults to 2048.

    .OUTPUTS
    [System.Security.Cryptography.X509Certificates.X509Certificate2] or $null.
    #>
    [CmdletBinding()]
    [OutputType([System.Security.Cryptography.X509Certificates.X509Certificate2])]
    param (
        [string]$Thumbprint,
        [string]$Subject,
        [int]$MinKeySize = 2048
    )

    if ([string]::IsNullOrEmpty($Thumbprint) -and [string]::IsNullOrEmpty($Subject)) {
        return $null
    }

    $isUsable = {
        param ($Candidate, $MinSize)
        if (-not $Candidate) { return $false }
        if (-not $Candidate.HasPrivateKey) { return $false }
        if ($Candidate.NotAfter -le [datetime]::UtcNow) { return $false }
        $keySize = $null
        try {
            if ($Candidate.PublicKey -and $Candidate.PublicKey.Key) {
                $keySize = $Candidate.PublicKey.Key.KeySize
            }
        }
        catch { $keySize = $null }
        if ($null -ne $keySize -and $keySize -lt $MinSize) { return $false }
        $true
    }

    $candidates = [System.Collections.Generic.List[object]]::new()

    if (-not [string]::IsNullOrEmpty($Thumbprint)) {
        foreach ($storeLocation in @('LocalMachine', 'CurrentUser')) {
            $storePath = "Cert:\$storeLocation\My\$Thumbprint"
            $found = Get-Item -LiteralPath $storePath -ErrorAction SilentlyContinue
            if ($found -and (& $isUsable $found $MinKeySize)) {
                $candidates.Add($found)
            }
        }
    }
    else {
        foreach ($storeLocation in @('LocalMachine', 'CurrentUser')) {
            $storePath = "Cert:\$storeLocation\My"
            $found = Get-ChildItem -Path $storePath -ErrorAction SilentlyContinue
            foreach ($c in $found) {
                if ($c.Subject -eq $Subject -and (& $isUsable $c $MinKeySize)) {
                    $candidates.Add($c)
                }
            }
        }
    }

    if ($candidates.Count -eq 0) { return $null }
    ($candidates | Sort-Object -Property NotAfter -Descending)[0]
}
