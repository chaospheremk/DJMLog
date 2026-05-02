BeforeAll {
    Import-Module "$PSScriptRoot\..\DJMLog.psd1" -Force

    # Build a self-signed RSA cert so we can sign + verify a real JWT.
    $req  = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
        'CN=DJMLog-JwtAssertion-Test',
        [System.Security.Cryptography.RSA]::Create(2048),
        [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $script:TestCert = $req.CreateSelfSigned(
        [System.DateTimeOffset]::UtcNow.AddMinutes(-5),
        [System.DateTimeOffset]::UtcNow.AddDays(30))
}

Describe 'New-DJMJwtAssertion' {

    It 'returns a three-segment compact JWT' {
        $jwt = InModuleScope DJMLog -ArgumentList ($script:TestCert) {
            param ($cert)
            New-DJMJwtAssertion -Certificate $cert -Audience 'https://login.test/example/oauth2/v2.0/token' -ClientId 'app-id'
        }
        $jwt | Should -Not -BeNullOrEmpty
        ($jwt -split '\.').Count | Should -Be 3
    }

    It 'sets x5t header to base64url-encoded thumbprint bytes' {
        $jwt = InModuleScope DJMLog -ArgumentList ($script:TestCert) {
            param ($cert)
            New-DJMJwtAssertion -Certificate $cert -Audience 'aud' -ClientId 'cid'
        }
        $headerB64 = ($jwt -split '\.')[0]
        $padded = $headerB64.Replace('-', '+').Replace('_', '/')
        switch ($padded.Length % 4) { 2 { $padded += '==' } 3 { $padded += '=' } }
        $headerJson = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($padded))
        $header     = $headerJson | ConvertFrom-Json
        $header.alg | Should -Be 'RS256'
        $header.typ | Should -Be 'JWT'

        $expectedX5t = [System.Convert]::ToBase64String(
            [System.Convert]::FromHexString($script:TestCert.Thumbprint)
        ).TrimEnd('=').Replace('+', '-').Replace('/', '_')
        $header.x5t | Should -Be $expectedX5t
    }

    It 'populates payload claims (aud, iss, sub, jti, nbf, exp)' {
        $aud = 'https://login.microsoftonline.us/<tenant>/oauth2/v2.0/token'
        $cid = 'app-id-001'
        $jwt = InModuleScope DJMLog -ArgumentList ($script:TestCert), $aud, $cid {
            param ($cert, $aud, $cid)
            New-DJMJwtAssertion -Certificate $cert -Audience $aud -ClientId $cid -LifetimeSeconds 600
        }
        $payloadB64 = ($jwt -split '\.')[1]
        $padded = $payloadB64.Replace('-', '+').Replace('_', '/')
        switch ($padded.Length % 4) { 2 { $padded += '==' } 3 { $padded += '=' } }
        $payload = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($padded)) | ConvertFrom-Json

        $payload.aud | Should -Be $aud
        $payload.iss | Should -Be $cid
        $payload.sub | Should -Be $cid
        $payload.jti | Should -Not -BeNullOrEmpty
        $payload.exp | Should -BeGreaterThan $payload.nbf
        ($payload.exp - $payload.nbf) | Should -Be 600
    }

    It 'produces a signature that verifies against the certificate public key' {
        $jwt = InModuleScope DJMLog -ArgumentList ($script:TestCert) {
            param ($cert)
            New-DJMJwtAssertion -Certificate $cert -Audience 'aud' -ClientId 'cid'
        }
        $segments = $jwt -split '\.'
        $unsigned = "$($segments[0]).$($segments[1])"
        $sigPad   = $segments[2].Replace('-', '+').Replace('_', '/')
        switch ($sigPad.Length % 4) { 2 { $sigPad += '==' } 3 { $sigPad += '=' } }
        $sigBytes = [System.Convert]::FromBase64String($sigPad)

        $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($script:TestCert)
        $verified = $rsa.VerifyData(
            [System.Text.Encoding]::UTF8.GetBytes($unsigned),
            $sigBytes,
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
        $verified | Should -BeTrue
    }

    It 'throws when the certificate has no usable RSA private key' {
        # Strip the private key by re-importing the public-only cert.
        $publicOnly = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
            $script:TestCert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))
        {
            InModuleScope DJMLog -ArgumentList $publicOnly {
                param ($cert)
                New-DJMJwtAssertion -Certificate $cert -Audience 'aud' -ClientId 'cid'
            }
        } | Should -Throw
    }
}
