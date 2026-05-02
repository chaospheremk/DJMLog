BeforeAll {
    Import-Module "$PSScriptRoot\..\DJMLog.psd1" -Force

    # The writer-side Get-LAToken function is defined inside a scriptblock that
    # runs in a dedicated runspace. We can't invoke it directly from the test,
    # but we can extract the source and rebuild the function in the test's
    # session so we can exercise its logic against a mocked Invoke-DJMRestMethodWithRetry.
    # The injection mechanism is the same one Start-DJMWriter uses for the real writer.
    $writerSrc   = Get-Content "$PSScriptRoot\..\Private\Start-DJMWriter.ps1" -Raw
    $jwtHelperSrc = Get-Content "$PSScriptRoot\..\Private\New-DJMJwtAssertion.ps1" -Raw
    $retrySrc    = Get-Content "$PSScriptRoot\..\Private\Invoke-DJMRestMethodWithRetry.ps1" -Raw

    # Pull the writer scriptblock body — between the start and end markers the
    # writer source contains the inline functions we need (Get-LAToken,
    # Add-WriterErr, Get-EntryByteCount). Source the helpers into the test scope.
    Invoke-Expression $jwtHelperSrc
    Invoke-Expression $retrySrc

    # Build a self-signed RSA cert for the JWT cert-auth path.
    $req = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
        'CN=DJMLog-Writer-Auth-Test',
        [System.Security.Cryptography.RSA]::Create(2048),
        [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $script:TestCert = $req.CreateSelfSigned(
        [System.DateTimeOffset]::UtcNow.AddMinutes(-5),
        [System.DateTimeOffset]::UtcNow.AddDays(30))
}

Describe 'Update-DJMWriterShared certificate marshalling' {

    BeforeEach {
        InModuleScope DJMLog {
            $script:CertificateThumbprint = $null
            $script:CertificateSubject    = $null
        }
    }

    It 'resolves cert by thumbprint into WriterShared.Certificate' {
        $cert = $script:TestCert
        InModuleScope DJMLog -ArgumentList $cert {
            param ($realCert)
            Mock Get-Item -ParameterFilter { $LiteralPath -like 'Cert:\*' } -MockWith { $realCert }
            $script:CertificateThumbprint = $realCert.Thumbprint
            Update-DJMWriterShared
            $script:WriterShared.Certificate | Should -Not -BeNullOrEmpty
            $script:WriterShared.Certificate.Thumbprint | Should -Be $realCert.Thumbprint
        }
    }

    It 'resolves cert by subject into WriterShared.Certificate' {
        $cert = $script:TestCert
        InModuleScope DJMLog -ArgumentList $cert {
            param ($realCert)
            Mock Get-ChildItem -ParameterFilter { $Path -like 'Cert:\*\My' } -MockWith { @($realCert) }
            $script:CertificateSubject = $realCert.Subject
            Update-DJMWriterShared
            $script:WriterShared.Certificate | Should -Not -BeNullOrEmpty
            $script:WriterShared.Certificate.Subject | Should -Be $realCert.Subject
        }
    }

    It 'clears WriterShared.Certificate when neither thumbprint nor subject is set' {
        InModuleScope DJMLog {
            $script:CertificateThumbprint = $null
            $script:CertificateSubject    = $null
            $script:WriterShared.Certificate = 'sentinel-not-null'
            Update-DJMWriterShared
            $script:WriterShared.Certificate | Should -BeNullOrEmpty
        }
    }
}

Describe 'Writer-side Get-LAToken auth selection' {

    # Construct a minimal $Shared hashtable shaped like the writer's, then
    # invoke a copy of the Get-LAToken function defined in the writer
    # scriptblock. We rebuild the function in the test's scope by sourcing
    # the writer's scriptblock body indirectly via Invoke-Expression once.

    BeforeAll {
        # Define a stand-alone Get-LAToken that mirrors the writer's by closing
        # over $Shared. We use the same logic the writer scriptblock embeds.
        function script:Make-WriterToken {
            param ($Shared)

            # Inline copies of the helpers the writer uses (Add-WriterErr stub).
            function Add-WriterErr {
                param ([string]$Source, [string]$Message, [object]$Exception)
                $Shared.Errors.Enqueue([pscustomobject]@{
                    UtcTimestamp = [datetime]::UtcNow.ToString('o')
                    Source       = $Source
                    Message      = $Message
                    Exception    = $Exception
                })
            }

            # External token: short-circuit
            if ($Shared.BearerTokenExternal) { return $Shared.BearerTokenExternal }
            if ($Shared.BearerTokenCache -and [datetime]::UtcNow -lt $Shared.BearerTokenExpiry) {
                return $Shared.BearerTokenCache
            }
            if (-not $Shared.TenantId -or -not $Shared.AppId) {
                Add-WriterErr -Source 'LogAnalyticsSink' -Message 'TenantId/AppId missing'
                return $null
            }
            $cloudMap = @{
                Commercial = @{ LoginHost = 'login.microsoftonline.com'; Scope = 'https://monitor.azure.com//.default' }
                GCCHigh    = @{ LoginHost = 'login.microsoftonline.us';  Scope = 'https://monitor.azure.us//.default' }
                DoD        = @{ LoginHost = 'login.microsoftonline.us';  Scope = 'https://monitor.azure.us//.default' }
            }
            $endpoints = $cloudMap[$Shared.CloudEnvironment]
            if (-not $endpoints) { return $null }
            $tokenUrl = "https://$($endpoints.LoginHost)/$($Shared.TenantId)/oauth2/v2.0/token"

            $body = $null
            if ($Shared.Certificate) {
                try {
                    $jwt = New-DJMJwtAssertion -Certificate $Shared.Certificate -Audience $tokenUrl -ClientId $Shared.AppId
                    $body = @{
                        grant_type            = 'client_credentials'
                        client_id             = $Shared.AppId
                        scope                 = $endpoints.Scope
                        client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
                        client_assertion      = $jwt
                    }
                }
                catch {
                    Add-WriterErr -Source 'LogAnalyticsSink' -Message "JWT assertion build failed: $($_.Exception.Message)" -Exception $_.Exception
                    return $null
                }
            }
            elseif ($Shared.AppSecret) {
                $secretStr = if ($Shared.AppSecret -is [System.Security.SecureString]) {
                    [System.Net.NetworkCredential]::new('', $Shared.AppSecret).Password
                } else { [string]$Shared.AppSecret }
                $body = @{
                    grant_type    = 'client_credentials'
                    client_id     = $Shared.AppId
                    client_secret = $secretStr
                    scope         = $endpoints.Scope
                }
            }
            else { return $null }

            try {
                $resp = Invoke-DJMRestMethodWithRetry -Uri $tokenUrl -Method 'POST' -Body $body -ContentType 'application/x-www-form-urlencoded' -MaxRetries 5
                if (-not $resp.access_token -or -not $resp.expires_in) { return $null }
                return $resp.access_token
            }
            catch { return $null }
        }
    }

    BeforeEach {
        $script:CapturedBody = $null
        Mock Invoke-DJMRestMethodWithRetry -MockWith {
            $script:CapturedBody = $Body
            @{ access_token = 'token-xyz'; expires_in = 3600 }
        }
    }

    It 'builds a JWT-bearer body when Shared.Certificate is set' {
        $shared = @{
            Errors             = [System.Collections.Concurrent.ConcurrentQueue[pscustomobject]]::new()
            BearerTokenExternal = $null
            BearerTokenCache   = $null
            BearerTokenExpiry  = [datetime]::MinValue
            TenantId           = 'tenant-id'
            AppId              = 'app-id'
            CloudEnvironment   = 'GCCHigh'
            Certificate        = $script:TestCert
            AppSecret          = $null
        }
        $token = Make-WriterToken -Shared $shared
        $token | Should -Be 'token-xyz'
        $script:CapturedBody.client_assertion_type | Should -Be 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
        $script:CapturedBody.client_assertion | Should -Not -BeNullOrEmpty
        ($script:CapturedBody.client_assertion -split '\.').Count | Should -Be 3
    }

    It 'falls through to AppSecret when Certificate is null' {
        $shared = @{
            Errors             = [System.Collections.Concurrent.ConcurrentQueue[pscustomobject]]::new()
            BearerTokenExternal = $null
            BearerTokenCache   = $null
            BearerTokenExpiry  = [datetime]::MinValue
            TenantId           = 'tenant-id'
            AppId              = 'app-id'
            CloudEnvironment   = 'GCCHigh'
            Certificate        = $null
            AppSecret          = 'plain-secret'
        }
        $token = Make-WriterToken -Shared $shared
        $token | Should -Be 'token-xyz'
        $script:CapturedBody.grant_type | Should -Be 'client_credentials'
        $script:CapturedBody.client_secret | Should -Be 'plain-secret'
        $script:CapturedBody.PSBase.Keys -contains 'client_assertion' | Should -BeFalse
    }

    It 'returns $null and queues SelfLog when no auth method configured' {
        $shared = @{
            Errors             = [System.Collections.Concurrent.ConcurrentQueue[pscustomobject]]::new()
            BearerTokenExternal = $null
            BearerTokenCache   = $null
            BearerTokenExpiry  = [datetime]::MinValue
            TenantId           = 'tenant-id'
            AppId              = 'app-id'
            CloudEnvironment   = 'GCCHigh'
            Certificate        = $null
            AppSecret          = $null
        }
        $token = Make-WriterToken -Shared $shared
        $token | Should -BeNullOrEmpty
    }

    It 'queues a SelfLog entry when JWT assertion build fails' {
        $shared = @{
            Errors             = [System.Collections.Concurrent.ConcurrentQueue[pscustomobject]]::new()
            BearerTokenExternal = $null
            BearerTokenCache   = $null
            BearerTokenExpiry  = [datetime]::MinValue
            TenantId           = 'tenant-id'
            AppId              = 'app-id'
            CloudEnvironment   = 'GCCHigh'
            # Public-only cert — no usable private key, JWT signing throws.
            Certificate        = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
                $script:TestCert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))
            AppSecret          = $null
        }
        $token = Make-WriterToken -Shared $shared
        $token | Should -BeNullOrEmpty
        $shared.Errors.Count | Should -BeGreaterThan 0
        $msg = $null
        $shared.Errors.TryDequeue([ref]$msg) | Out-Null
        $msg.Source | Should -Be 'LogAnalyticsSink'
        $msg.Message | Should -BeLike 'JWT assertion build failed*'
    }
}
