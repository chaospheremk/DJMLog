function Invoke-DJMRestMethodWithRetry {
    <#
    .SYNOPSIS
    Internal HTTP wrapper around Invoke-RestMethod with retry/backoff.

    .DESCRIPTION
    Issues an HTTP request via Invoke-RestMethod with retry logic for transient
    failures. Honors the Retry-After header on 429 (seconds or HTTP-date),
    applies exponential backoff with ±20% jitter on 5xx, and propagates 4xx
    other than 429 immediately.

    Backoff schedule: base 500 ms, factor 2 (i.e. 0.5s, 1s, 2s, 4s, 8s …) with
    jitter applied per wait. -MaxRetries is the total attempt count, not the
    retry count — default is 5, meaning up to 5 total HTTP attempts before the
    final failure is rethrown.

    Used by Get-DJMBearerToken (token endpoint) and Send-DJMLogBuffer (Logs
    Ingestion API) so transient throttling and gateway failures don't trip the
    circuit breaker on the first hiccup.

    .PARAMETER Uri
    Target URI.

    .PARAMETER Method
    HTTP method (GET, POST, etc.).

    .PARAMETER Headers
    Hashtable of request headers.

    .PARAMETER Body
    Request body (string).

    .PARAMETER ContentType
    Request Content-Type header (e.g. 'application/json').

    .PARAMETER MaxRetries
    Maximum number of total attempts. Defaults to 5.

    .PARAMETER TimeoutSec
    Per-request timeout passed through to Invoke-RestMethod. Defaults to 30.

    .PARAMETER SleepProvider
    ScriptBlock that takes a single argument (seconds, double) and is invoked
    between retries. Defaults to Start-Sleep. Overridable so tests can avoid
    real sleeps and capture the requested wait durations.

    .OUTPUTS
    The response object emitted by Invoke-RestMethod.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [string]$Method,

        [hashtable]$Headers,

        [object]$Body,

        [string]$ContentType,

        [ValidateRange(1, 50)]
        [int]$MaxRetries = 5,

        [ValidateRange(1, 600)]
        [int]$TimeoutSec = 30,

        [scriptblock]$SleepProvider = { param([double]$Seconds) Start-Sleep -Seconds $Seconds }
    )

    $rng = [System.Random]::new()
    $attempt = 0

    while ($true) {
        $attempt++
        try {
            $invokeParams = @{
                Uri        = $Uri
                Method     = $Method
                TimeoutSec = $TimeoutSec
                ErrorAction = 'Stop'
            }
            if ($Headers)     { $invokeParams.Headers     = $Headers }
            if ($Body)        { $invokeParams.Body        = $Body }
            if ($ContentType) { $invokeParams.ContentType = $ContentType }

            return Invoke-RestMethod @invokeParams
        }
        catch {
            $statusCode  = $null
            $retryAfter  = $null
            $exception   = $_.Exception

            # Try to extract HTTP status + Retry-After from various exception shapes
            $response = $null
            if ($exception.PSObject.Properties['Response'] -and $exception.Response) {
                $response = $exception.Response
            }
            elseif ($exception.Data -and $exception.Data.Contains('HttpResponseMessage')) {
                $response = $exception.Data['HttpResponseMessage']
            }

            if ($response) {
                if ($response.PSObject.Properties['StatusCode'] -and $null -ne $response.StatusCode) {
                    $statusCode = [int]$response.StatusCode
                }
                if ($response.PSObject.Properties['Headers'] -and $response.Headers) {
                    $hdrs = $response.Headers
                    if ($hdrs -is [System.Net.Http.Headers.HttpResponseHeaders]) {
                        if ($hdrs.RetryAfter) {
                            if ($hdrs.RetryAfter.Delta) {
                                $retryAfter = $hdrs.RetryAfter.Delta.TotalSeconds
                            }
                            elseif ($hdrs.RetryAfter.Date) {
                                $retryAfter = ($hdrs.RetryAfter.Date.UtcDateTime - [datetime]::UtcNow).TotalSeconds
                            }
                        }
                    }
                    elseif ($hdrs.PSObject.Properties['Retry-After']) {
                        # Defensive fallback for synthetic test harnesses that
                        # attach a plain hashtable-shaped header bag. Real
                        # HttpResponseMessage instances always take the typed
                        # branch above. Cast may fail on HTTP-date strings; we
                        # swallow so the request still backs off via jitter.
                        try { $retryAfter = [double]$hdrs['Retry-After'] } catch { $retryAfter = $null }
                    }
                }
            }
            if (-not $statusCode -and $exception.PSObject.Properties['StatusCode'] -and $null -ne $exception.StatusCode) {
                $statusCode = [int]$exception.StatusCode
            }

            # Only retry on documented transient HTTP statuses. Generic / network
            # errors with no resolvable status code are surfaced immediately so
            # callers (and the circuit breaker) don't block on unknown failures.
            $retryable = $false
            if ($statusCode -eq 429) {
                $retryable = $true
            }
            elseif ($statusCode -ge 500 -and $statusCode -le 599) {
                $retryable = $true
            }

            if (-not $retryable -or $attempt -ge $MaxRetries) {
                throw
            }

            # Compute wait
            if ($retryAfter -and $retryAfter -gt 0) {
                $waitSec = [double]$retryAfter
            }
            else {
                $baseMs   = 500.0 * [math]::Pow(2, $attempt - 1)
                $jitter   = ($rng.NextDouble() * 0.4) - 0.2     # ±20%
                $waitSec  = ($baseMs * (1.0 + $jitter)) / 1000.0
                if ($waitSec -lt 0.4) { $waitSec = 0.4 }
            }

            & $SleepProvider $waitSec
        }
    }
}
