function Get-DJMManagedIdentityToken {
    <#
    .SYNOPSIS
    Acquires a bearer token from the Azure Instance Metadata Service (IMDS).

    .DESCRIPTION
    Internal helper. Issues a GET against the IMDS endpoint
    (http://169.254.169.254/metadata/identity/oauth2/token) using the
    `Metadata: true` header, returning the OAuth response object verbatim.
    System-assigned MI is requested when -ClientId is omitted; pass -ClientId
    to target a specific user-assigned managed identity.

    Native HTTP rather than Az.Accounts so DJMLog stays dependency-free across
    runspace boundaries (ADR-029). The IMDS contract is identical across
    Commercial / GCCHigh / DoD; only the -Resource value differs per cloud.

    .PARAMETER Resource
    Target resource URI for the token, e.g. 'https://monitor.azure.com' or
    'https://monitor.azure.us'. Trailing slashes are accepted by IMDS.

    .PARAMETER ClientId
    Optional user-assigned managed-identity client ID. When omitted, the
    system-assigned MI on the host (if any) is used.

    .PARAMETER TimeoutSec
    Per-request timeout. Defaults to 5 seconds — IMDS is link-local and
    failures should surface fast.

    .OUTPUTS
    [pscustomobject] with at least the access_token and expires_in properties.
    Throws on non-2xx HTTP responses or transport errors.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [string]$Resource,

        [string]$ClientId,

        [ValidateRange(1, 60)]
        [int]$TimeoutSec = 5
    )

    $query = "api-version=2018-02-01&resource=$([uri]::EscapeDataString($Resource))"
    if (-not [string]::IsNullOrEmpty($ClientId)) {
        $query += "&client_id=$([uri]::EscapeDataString($ClientId))"
    }
    $uri = "http://169.254.169.254/metadata/identity/oauth2/token?$query"

    $invokeParams = @{
        Uri        = $uri
        Method     = 'GET'
        Headers    = @{ Metadata = 'true' }
        TimeoutSec = $TimeoutSec
        MaxRetries = 3
    }
    Invoke-DJMRestMethodWithRetry @invokeParams
}
