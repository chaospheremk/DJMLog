function New-DJMJwtAssertion {
    <#
    .SYNOPSIS
    Builds a signed RS256 client_assertion JWT from an X.509 certificate.

    .DESCRIPTION
    Internal helper. Constructs the JWT header (alg=RS256, typ=JWT, x5t from the
    certificate thumbprint), payload (aud / iss / sub / jti / nbf / exp), and
    signs the unsigned token via the certificate's RSA private key
    (RSASignaturePadding.Pkcs1, SHA-256). Returns the three-segment compact JWT
    string suitable for the OAuth2 client_credentials JWT-bearer flow.

    No Cert: PSDrive dependency — the certificate is consumed as a regular
    X509Certificate2 instance, so this runs unchanged inside the writer runspace
    after the main runspace marshals the resolved cert into shared state.

    .PARAMETER Certificate
    The signing certificate. Must have a private key reachable via
    GetRSAPrivateKey().

    .PARAMETER Audience
    The token endpoint URL (aud claim).

    .PARAMETER ClientId
    The Entra app registration's application (client) ID. Used for both iss and
    sub claims.

    .PARAMETER LifetimeSeconds
    Token validity window. Defaults to 300 seconds.

    .OUTPUTS
    [string] Compact JWT (header.payload.signature, all base64url).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

        [Parameter(Mandatory)]
        [string]$Audience,

        [Parameter(Mandatory)]
        [string]$ClientId,

        [int]$LifetimeSeconds = 300
    )

    $thumbprintBytes = [System.Convert]::FromHexString($Certificate.Thumbprint)
    $x5t = [System.Convert]::ToBase64String($thumbprintBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')

    $nowEpoch = [long]([datetime]::UtcNow - [datetime]::new(1970, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)).TotalSeconds
    $expEpoch = $nowEpoch + $LifetimeSeconds

    $jwtHeader = @{ alg = 'RS256'; typ = 'JWT'; x5t = $x5t } | ConvertTo-Json -Compress
    $jwtPayload = @{
        aud = $Audience
        iss = $ClientId
        sub = $ClientId
        jti = (New-Guid).Guid
        nbf = $nowEpoch
        exp = $expEpoch
    } | ConvertTo-Json -Compress

    $toBase64Url = {
        param ([string]$Text)
        [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Text)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    }

    $headerB64   = & $toBase64Url $jwtHeader
    $payloadB64  = & $toBase64Url $jwtPayload
    $unsignedJwt = "$headerB64.$payloadB64"

    # GetRSAPrivateKey is an extension method on X509Certificate2 in modern .NET;
    # PowerShell's instance-method resolution doesn't pick it up reliably (varies
    # by host / .NET version), so call the static form on RSACertificateExtensions
    # explicitly. Same call pattern works on PS 7.4 + 7.5 across Windows/Linux.
    $rsaKey = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($Certificate)
    if (-not $rsaKey) {
        throw "New-DJMJwtAssertion: certificate '$($Certificate.Thumbprint)' has no usable RSA private key."
    }
    $signatureBytes = $rsaKey.SignData(
        [System.Text.Encoding]::UTF8.GetBytes($unsignedJwt),
        [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
    )
    $signatureB64 = [System.Convert]::ToBase64String($signatureBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')

    "$unsignedJwt.$signatureB64"
}
