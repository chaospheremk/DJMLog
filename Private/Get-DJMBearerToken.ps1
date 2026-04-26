function Get-DJMBearerToken {
    <#
    .SYNOPSIS
    Acquires and caches an OAuth2 bearer token for Azure Log Analytics ingestion.

    .DESCRIPTION
    Internal helper used by Send-DJMLogBuffer. Returns a cached token when still
    valid (5-minute safety margin), otherwise acquires a new one via the
    configured authentication method.

    Auth priority:
      1. BearerTokenExternal  - user-supplied token, returned as-is
      2. CertificateThumbprint - load cert by thumbprint, JWT assertion flow
      3. CertificateSubject    - find best cert by subject, JWT assertion flow
      4. AppSecret             - client_credentials with client_secret

    Cloud-aware endpoints:
      Commercial: login.microsoftonline.com / https://monitor.azure.com//.default
      GCCHigh/DoD: login.microsoftonline.us / https://monitor.azure.us//.default

    .OUTPUTS
    [string] Bearer token, or $null on failure.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param ()

    # 1. External token — user manages expiry
    if ($script:BearerTokenExternal) {
        $script:BearerTokenExternal
        return
    }

    # 2. Return cached token if still valid (5-min safety margin)
    if ($script:BearerToken -and [datetime]::UtcNow -lt $script:TokenExpiry) {
        $script:BearerToken
        return
    }

    # Require TenantId + AppId for all OAuth2 flows
    if (-not $script:TenantId -or -not $script:AppId) {
        Write-Warning 'Get-DJMBearerToken: TenantId and AppId are required for token acquisition. Use Set-DJMLogConfig or supply -BearerToken.'
        return
    }

    # Resolve cloud endpoints
    $cloudMap = @{
        Commercial = @{ LoginHost = 'login.microsoftonline.com'; Scope = 'https://monitor.azure.com//.default' }
        GCCHigh    = @{ LoginHost = 'login.microsoftonline.us';  Scope = 'https://monitor.azure.us//.default' }
        DoD        = @{ LoginHost = 'login.microsoftonline.us';  Scope = 'https://monitor.azure.us//.default' }
    }
    $endpoints  = $cloudMap[$script:CloudEnvironment]
    if (-not $endpoints) {
        Write-Warning "Get-DJMBearerToken: unknown CloudEnvironment '$($script:CloudEnvironment)'. Valid values: Commercial, GCCHigh, DoD."
        return
    }
    $loginHost  = $endpoints.LoginHost
    $tokenScope = $endpoints.Scope
    $tokenUrl   = "https://$loginHost/$($script:TenantId)/oauth2/v2.0/token"

    $body = $null

    # 3. Certificate auth (thumbprint or subject)
    $cert = $null
    if ($script:CertificateThumbprint) {
        foreach ($storeLocation in @('LocalMachine', 'CurrentUser')) {
            $storePath = "Cert:\$storeLocation\My\$($script:CertificateThumbprint)"
            $cert = Get-Item -LiteralPath $storePath -ErrorAction SilentlyContinue
            if ($cert -and $cert.HasPrivateKey) { break }
            $cert = $null
        }
        if (-not $cert) {
            Write-Warning "Get-DJMBearerToken: no certificate with thumbprint '$($script:CertificateThumbprint)' and a private key was found."
            return
        }
    }
    elseif ($script:CertificateSubject) {
        $candidates = [System.Collections.Generic.List[System.Security.Cryptography.X509Certificates.X509Certificate2]]::new()
        foreach ($storeLocation in @('LocalMachine', 'CurrentUser')) {
            $storePath = "Cert:\$storeLocation\My"
            $found = Get-ChildItem -Path $storePath -ErrorAction SilentlyContinue
            foreach ($c in $found) {
                if ($c.Subject -eq $script:CertificateSubject -and $c.NotAfter -gt [datetime]::UtcNow -and $c.HasPrivateKey) {
                    $candidates.Add($c)
                }
            }
        }
        if ($candidates.Count -eq 0) {
            Write-Warning "Get-DJMBearerToken: no valid certificate with subject '$($script:CertificateSubject)' was found."
            return
        }
        # Pick the one with the latest NotAfter (most recently issued)
        $cert = ($candidates | Sort-Object -Property NotAfter -Descending)[0]
    }

    if ($cert) {
        # Build JWT assertion
        $thumbprintBytes = [System.Convert]::FromHexString($cert.Thumbprint)
        $x5t = [System.Convert]::ToBase64String($thumbprintBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')

        $nowEpoch = [long]([datetime]::UtcNow - [datetime]::new(1970, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)).TotalSeconds
        $expEpoch = $nowEpoch + 300  # 5 minutes

        $jwtHeader = @{ alg = 'RS256'; typ = 'JWT'; x5t = $x5t } | ConvertTo-Json -Compress
        $jwtPayload = @{
            aud = "https://$loginHost/$($script:TenantId)/oauth2/v2.0/token"
            iss = $script:AppId
            sub = $script:AppId
            jti = (New-Guid).Guid
            nbf = $nowEpoch
            exp = $expEpoch
        } | ConvertTo-Json -Compress

        $toBase64Url = {
            param ([string]$Text)
            [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Text)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
        }

        $headerB64  = & $toBase64Url $jwtHeader
        $payloadB64 = & $toBase64Url $jwtPayload
        $unsignedJwt = "$headerB64.$payloadB64"

        try {
            $rsaKey = $cert.GetRSAPrivateKey()
            $signatureBytes = $rsaKey.SignData(
                [System.Text.Encoding]::UTF8.GetBytes($unsignedJwt),
                [System.Security.Cryptography.HashAlgorithmName]::SHA256,
                [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
            )
            $signatureB64 = [System.Convert]::ToBase64String($signatureBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
        }
        catch {
            Write-Warning "Get-DJMBearerToken: failed to sign JWT assertion: $_"
            Add-DJMInternalError -Source 'Get-DJMBearerToken' -Message 'JWT assertion signing failed' -Exception $_.Exception
            return
        }

        $signedJwt = "$unsignedJwt.$signatureB64"

        $body = @{
            grant_type            = 'client_credentials'
            client_id             = $script:AppId
            scope                 = $tokenScope
            client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
            client_assertion      = $signedJwt
        }
    }
    elseif ($script:AppSecret) {
        # 4. Client secret flow.
        # Pull the plaintext into a local [char[]] via NetworkCredential, build the
        # body, then zero the buffer in finally so the secret leaves the process
        # heap as soon as the request body is constructed. The body hashtable still
        # holds the string until Invoke-RestMethod runs; that is unavoidable without
        # a managed-identity path (deferred to v2.x per the roadmap).
        $secretBuf = $null
        try {
            if ($script:AppSecret -is [System.Security.SecureString]) {
                $netCred   = [System.Net.NetworkCredential]::new('', $script:AppSecret)
                $secretBuf = $netCred.Password.ToCharArray()
            }
            else {
                # Back-compat: string input was already converted to SecureString in
                # Set-DJMLogConfig, but if a caller bypassed that path we still cope.
                $secretBuf = ([string]$script:AppSecret).ToCharArray()
            }

            $body = @{
                grant_type    = 'client_credentials'
                client_id     = $script:AppId
                client_secret = [string]::new($secretBuf)
                scope         = $tokenScope
            }
        }
        finally {
            if ($secretBuf) { [System.Array]::Clear($secretBuf, 0, $secretBuf.Length) }
        }
    }
    else {
        Write-Warning 'Get-DJMBearerToken: no authentication method configured. Supply BearerToken, CertificateThumbprint, CertificateSubject, or AppSecret via Set-DJMLogConfig.'
        return
    }

    # Acquire token
    try {
        $response = Invoke-RestMethod -Uri $tokenUrl -Method POST -Body $body -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
        if (-not $response.access_token -or -not $response.expires_in) {
            Write-Warning 'Get-DJMBearerToken: token endpoint returned an incomplete response (missing access_token or expires_in).'
            Add-DJMInternalError -Source 'Get-DJMBearerToken' -Message 'Token endpoint returned incomplete response (missing access_token or expires_in)'
            return
        }
        $script:BearerToken = $response.access_token
        $script:TokenExpiry = [datetime]::UtcNow.AddSeconds($response.expires_in - 300)  # 5-min safety margin
        $script:BearerToken
    }
    catch {
        Write-Warning "Get-DJMBearerToken: token acquisition failed: $_"
        Add-DJMInternalError -Source 'Get-DJMBearerToken' -Message "Token acquisition failed: $($_.Exception.Message)" -Exception $_.Exception
        return
    }
}
