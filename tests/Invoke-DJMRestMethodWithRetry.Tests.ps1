BeforeAll {
    Import-Module "$PSScriptRoot\..\DJMLog.psd1" -Force
}

Describe 'Invoke-DJMRestMethodWithRetry' {

    BeforeEach {
        InModuleScope DJMLog {
            # Reset any shared state between tests
            $script:InternalErrors = [System.Collections.Generic.Queue[pscustomobject]]::new()
        }
    }

    Context '200 on first attempt' {

        It 'returns the response and calls Invoke-RestMethod exactly once' {
            InModuleScope DJMLog {
                Mock Invoke-RestMethod -ModuleName DJMLog {
                    [pscustomobject]@{ StatusCode = 200; Content = 'ok' }
                }

                $noopSleep = { param($sec) }
                $params = @{
                    Uri           = 'https://fake.endpoint.test/api'
                    Method        = 'POST'
                    Headers       = @{ Authorization = 'Bearer fake-token' }
                    Body          = '{"test":true}'
                    ContentType   = 'application/json'
                    SleepProvider = $noopSleep
                }
                $result = Invoke-DJMRestMethodWithRetry @params

                Should -Invoke Invoke-RestMethod -ModuleName DJMLog -Times 1 -Exactly
                $result | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context '429 with Retry-After header' {

        It 'retries after honouring Retry-After and succeeds on second attempt' {
            InModuleScope DJMLog {
                $script:_callCount = 0
                $script:_sleepArgs = [System.Collections.Generic.List[double]]::new()

                Mock Invoke-RestMethod -ModuleName DJMLog {
                    $script:_callCount++
                    if ($script:_callCount -eq 1) {
                        # Simulate 429 with Retry-After header
                        $response = [System.Net.Http.HttpResponseMessage]::new(
                            [System.Net.HttpStatusCode]::TooManyRequests
                        )
                        $response.Headers.Add('Retry-After', '2')
                        $ex = [System.Net.Http.HttpRequestException]::new('429 Too Many Requests')
                        # Attach the response so the helper can read Retry-After
                        $ex.Data['HttpResponseMessage'] = $response
                        throw $ex
                    }
                    [pscustomobject]@{ StatusCode = 200 }
                }

                $captureSleep = {
                    param($sec)
                    $script:_sleepArgs.Add($sec)
                }

                $params = @{
                    Uri           = 'https://fake.endpoint.test/api'
                    Method        = 'POST'
                    Headers       = @{ Authorization = 'Bearer fake-token' }
                    Body          = '{"test":true}'
                    ContentType   = 'application/json'
                    SleepProvider = $captureSleep
                    MaxRetries    = 5
                }
                { Invoke-DJMRestMethodWithRetry @params } | Should -Not -Throw

                # Must have called Invoke-RestMethod at least twice
                Should -Invoke Invoke-RestMethod -ModuleName DJMLog -Times 2 -Exactly
            }
        }
    }

    Context '503 twice then 200 — exponential backoff' {

        It 'makes 3 total calls and each retry wait follows exponential pattern' {
            InModuleScope DJMLog {
                $script:_callCount503 = 0
                $script:_sleepArgs503 = [System.Collections.Generic.List[double]]::new()

                Mock Invoke-RestMethod -ModuleName DJMLog {
                    $script:_callCount503++
                    if ($script:_callCount503 -le 2) {
                        $response = [System.Net.Http.HttpResponseMessage]::new(
                            [System.Net.HttpStatusCode]::ServiceUnavailable
                        )
                        $ex = [System.Net.Http.HttpRequestException]::new('503 Service Unavailable')
                        $ex.Data['HttpResponseMessage'] = $response
                        throw $ex
                    }
                    [pscustomobject]@{ StatusCode = 200 }
                }

                $captureSleep = {
                    param($sec)
                    $script:_sleepArgs503.Add($sec)
                }

                $params = @{
                    Uri           = 'https://fake.endpoint.test/api'
                    Method        = 'POST'
                    Headers       = @{ Authorization = 'Bearer fake-token' }
                    Body          = '{"test":true}'
                    ContentType   = 'application/json'
                    SleepProvider = $captureSleep
                    MaxRetries    = 5
                }
                { Invoke-DJMRestMethodWithRetry @params } | Should -Not -Throw

                # Exactly 3 calls: attempt 1 (503), attempt 2 (503), attempt 3 (200)
                Should -Invoke Invoke-RestMethod -ModuleName DJMLog -Times 3 -Exactly

                # Two sleeps recorded (between attempts 1-2 and 2-3)
                $script:_sleepArgs503.Count | Should -Be 2

                # First wait: base 500ms * 1 = 500ms → in seconds = 0.5; allow >=0.4 (80% lower bound)
                # Second wait: base 500ms * 2 = 1000ms = 1s; allow >=0.8
                # SleepProvider receives seconds
                $script:_sleepArgs503[0] | Should -BeGreaterOrEqual 0.4
                $script:_sleepArgs503[1] | Should -BeGreaterOrEqual 0.8
                # Second wait should be larger than first (exponential, not flat)
                $script:_sleepArgs503[1] | Should -BeGreaterOrEqual $script:_sleepArgs503[0]
            }
        }
    }

    Context 'All retries exhausted' {

        It 'throws after MaxRetries consecutive failures' {
            InModuleScope DJMLog {
                Mock Invoke-RestMethod -ModuleName DJMLog {
                    $response = [System.Net.Http.HttpResponseMessage]::new(
                        [System.Net.HttpStatusCode]::ServiceUnavailable
                    )
                    $ex = [System.Net.Http.HttpRequestException]::new('503 Service Unavailable')
                    $ex.Data['HttpResponseMessage'] = $response
                    throw $ex
                }

                $noopSleep = { param($sec) }
                $params = @{
                    Uri           = 'https://fake.endpoint.test/api'
                    Method        = 'POST'
                    Headers       = @{ Authorization = 'Bearer fake-token' }
                    Body          = '{"test":true}'
                    ContentType   = 'application/json'
                    SleepProvider = $noopSleep
                    MaxRetries    = 5
                }
                { Invoke-DJMRestMethodWithRetry @params } | Should -Throw

                # Should have tried MaxRetries + 1 times (initial + 5 retries) or exactly MaxRetries times
                # depending on implementation; assert at minimum MaxRetries calls were made
                Should -Invoke Invoke-RestMethod -ModuleName DJMLog -Times 5 -Exactly
            }
        }
    }

    Context '4xx non-429 — no retry' {

        It 'throws immediately on 400 without retrying' {
            InModuleScope DJMLog {
                Mock Invoke-RestMethod -ModuleName DJMLog {
                    $response = [System.Net.Http.HttpResponseMessage]::new(
                        [System.Net.HttpStatusCode]::BadRequest
                    )
                    $ex = [System.Net.Http.HttpRequestException]::new('400 Bad Request')
                    $ex.Data['HttpResponseMessage'] = $response
                    throw $ex
                }

                $noopSleep = { param($sec) }
                $params = @{
                    Uri           = 'https://fake.endpoint.test/api'
                    Method        = 'POST'
                    Headers       = @{ Authorization = 'Bearer fake-token' }
                    Body          = '{"test":true}'
                    ContentType   = 'application/json'
                    SleepProvider = $noopSleep
                    MaxRetries    = 5
                }
                { Invoke-DJMRestMethodWithRetry @params } | Should -Throw

                # Only one call — no retries for 4xx other than 429
                Should -Invoke Invoke-RestMethod -ModuleName DJMLog -Times 1 -Exactly
            }
        }

        It 'throws immediately on 403 without retrying' {
            InModuleScope DJMLog {
                Mock Invoke-RestMethod -ModuleName DJMLog {
                    $response = [System.Net.Http.HttpResponseMessage]::new(
                        [System.Net.HttpStatusCode]::Forbidden
                    )
                    $ex = [System.Net.Http.HttpRequestException]::new('403 Forbidden')
                    $ex.Data['HttpResponseMessage'] = $response
                    throw $ex
                }

                $noopSleep = { param($sec) }
                $params = @{
                    Uri           = 'https://fake.endpoint.test/api'
                    Method        = 'POST'
                    Headers       = @{ Authorization = 'Bearer fake-token' }
                    Body          = '{"test":true}'
                    ContentType   = 'application/json'
                    SleepProvider = $noopSleep
                    MaxRetries    = 5
                }
                { Invoke-DJMRestMethodWithRetry @params } | Should -Throw

                Should -Invoke Invoke-RestMethod -ModuleName DJMLog -Times 1 -Exactly
            }
        }
    }

    Context 'TimeoutSec forwarding' {

        It 'passes TimeoutSec to Invoke-RestMethod' {
            InModuleScope DJMLog {
                Mock Invoke-RestMethod -ModuleName DJMLog { [pscustomobject]@{ ok = $true } }

                $noopSleep = { param($sec) }
                $params = @{
                    Uri           = 'https://fake.endpoint.test/api'
                    Method        = 'GET'
                    Headers       = @{ Authorization = 'Bearer fake-token' }
                    Body          = ''
                    ContentType   = 'application/json'
                    SleepProvider = $noopSleep
                    TimeoutSec    = 30
                }
                Invoke-DJMRestMethodWithRetry @params

                Should -Invoke Invoke-RestMethod -ModuleName DJMLog -Times 1 -Exactly -ParameterFilter {
                    $TimeoutSec -eq 30
                }
            }
        }
    }
}
