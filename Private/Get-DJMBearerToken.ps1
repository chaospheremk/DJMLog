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

    # 3. Certificate auth (thumbprint or subject) — resolution and JWT signing
    # are factored out into Resolve-DJMCertificate / New-DJMJwtAssertion so the
    # writer runspace can reuse the JWT builder against a pre-resolved cert
    # marshalled in via $WriterShared.Certificate (per ADR-027).
    $cert = $null
    $minKeySize = 2048

    if ($script:CertificateThumbprint) {
        $cert = Resolve-DJMCertificate -Thumbprint $script:CertificateThumbprint -MinKeySize $minKeySize
        if (-not $cert) {
            Write-Warning "Get-DJMBearerToken: no valid certificate (not expired, has private key, key size >= $minKeySize bits) was found for thumbprint '$($script:CertificateThumbprint)'."
            return
        }
    }
    elseif ($script:CertificateSubject) {
        $cert = Resolve-DJMCertificate -Subject $script:CertificateSubject -MinKeySize $minKeySize
        if (-not $cert) {
            Write-Warning "Get-DJMBearerToken: no valid certificate (not expired, has private key, key size >= $minKeySize bits) with subject '$($script:CertificateSubject)' was found."
            return
        }
    }

    if ($cert) {
        try {
            $signedJwt = New-DJMJwtAssertion -Certificate $cert -Audience $tokenUrl -ClientId $script:AppId
        }
        catch {
            Write-Warning "Get-DJMBearerToken: failed to sign JWT assertion: $_"
            Add-DJMInternalError -Source 'Get-DJMBearerToken' -Message 'JWT assertion signing failed' -Exception $_.Exception
            return
        }

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

    # Acquire token via the shared retry helper so transient throttling doesn't
    # hammer the circuit breaker on the first failure.
    try {
        $retryParams = @{
            Uri         = $tokenUrl
            Method      = 'POST'
            Body        = $body
            ContentType = 'application/x-www-form-urlencoded'
            MaxRetries  = 5
        }
        $response = Invoke-DJMRestMethodWithRetry @retryParams
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
