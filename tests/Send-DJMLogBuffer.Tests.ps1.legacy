BeforeAll {
    Import-Module "$PSScriptRoot\..\DJMLog.psd1" -Force
}

Describe 'Send-DJMLogBuffer' {

    BeforeEach {
        InModuleScope DJMLog {
            $script:LogAnalyticsEnabled     = $true
            $script:CloudEnvironment        = 'GCCHigh'
            $script:DcrEndpointUri          = 'https://fake.ingest.monitor.azure.us'
            $script:DcrImmutableId          = 'dcr-fake'
            $script:DcrStreamName           = 'Custom-Test_CL'
            $script:TenantId                = 'tenant-id'
            $script:AppId                   = 'app-id'
            $script:AppSecret               = 'secret'
            $script:CertificateSubject      = $null
            $script:CertificateThumbprint   = $null
            $script:BearerToken             = $null
            $script:BearerTokenExternal     = 'fake-token'
            $script:TokenExpiry             = [datetime]::MinValue
            $script:FlushThreshold          = 100
            $script:MaxBufferSize           = 5000
            $script:MaxFlushRetries         = 3
            $script:FlushFailureCount       = 0
            $script:AutoFlushDisabled       = $false
            $script:AutoFlushOpenedAtUtc    = $null
            $script:LogBuffer               = [System.Collections.Generic.List[hashtable]]::new()
            $script:BufferByteTotal         = 0
            $script:MaxBufferBytes          = 52428800
            $script:HalfOpenAfterSeconds    = 300
        }
    }

    AfterEach {
        InModuleScope DJMLog {
            $script:LogAnalyticsEnabled     = $false
            $script:LogBuffer               = [System.Collections.Generic.List[hashtable]]::new()
            $script:BufferByteTotal         = 0
            $script:MaxBufferBytes          = 52428800
            $script:HalfOpenAfterSeconds    = 300
            $script:FlushFailureCount       = 0
            $script:AutoFlushDisabled       = $false
            $script:AutoFlushOpenedAtUtc    = $null
            $script:BearerTokenExternal     = $null
        }
    }

    Context 'Precondition checks' {

        It 'warns and returns when LogAnalyticsEnabled is false' {
            InModuleScope DJMLog { $script:LogAnalyticsEnabled = $false }
            Send-DJMLogBuffer -WarningVariable w -WarningAction SilentlyContinue
            $w | Should -Not -BeNullOrEmpty
        }

        It 'warns and returns when DcrEndpointUri is not set' {
            InModuleScope DJMLog { $script:DcrEndpointUri = $null }
            Send-DJMLogBuffer -WarningVariable w -WarningAction SilentlyContinue
            $w | Should -Not -BeNullOrEmpty
        }

        It 'warns and returns when DcrImmutableId is not set' {
            InModuleScope DJMLog { $script:DcrImmutableId = $null }
            Send-DJMLogBuffer -WarningVariable w -WarningAction SilentlyContinue
            $w | Should -Not -BeNullOrEmpty
        }

        It 'warns and returns when DcrStreamName is not set' {
            InModuleScope DJMLog { $script:DcrStreamName = $null }
            Send-DJMLogBuffer -WarningVariable w -WarningAction SilentlyContinue
            $w | Should -Not -BeNullOrEmpty
        }

        It 'returns silently when buffer is empty' {
            Send-DJMLogBuffer -WarningVariable w -WarningAction SilentlyContinue
            $w | Should -BeNullOrEmpty
        }

        It 'warns and returns when AutoFlushDisabled is true (without -Force)' {
            InModuleScope DJMLog {
                $script:AutoFlushDisabled = $true
                $script:LogBuffer.Add(@{ UtcTimestamp = '2026-01-01T00:00:00Z'; Level = 'INFO'; Message = 'test'; CorrelationId = 'cid' })
            }
            Send-DJMLogBuffer -WarningVariable w -WarningAction SilentlyContinue
            $w | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Successful flush' {

        BeforeEach {
            Mock Invoke-RestMethod -ModuleName DJMLog { }
            InModuleScope DJMLog {
                $script:LogBuffer.Add(@{ UtcTimestamp = '2026-01-01T00:00:00Z'; Level = 'INFO'; Message = 'entry1'; CorrelationId = 'cid1' })
                $script:LogBuffer.Add(@{ UtcTimestamp = '2026-01-01T00:00:01Z'; Level = 'WARN'; Message = 'entry2'; CorrelationId = 'cid2' })
                $script:FlushFailureCount = 2
                $script:AutoFlushDisabled = $true
            }
        }

        It 'clears the buffer after successful flush' {
            Send-DJMLogBuffer -Force
            InModuleScope DJMLog { $script:LogBuffer.Count } | Should -Be 0
        }

        It 'resets failure count to zero' {
            Send-DJMLogBuffer -Force
            InModuleScope DJMLog { $script:FlushFailureCount } | Should -Be 0
        }

        It 're-enables auto-flush' {
            Send-DJMLogBuffer -Force
            InModuleScope DJMLog { $script:AutoFlushDisabled } | Should -Be $false
        }

        It 'calls Invoke-RestMethod with the correct URI pattern' {
            Send-DJMLogBuffer -Force
            Should -Invoke Invoke-RestMethod -ModuleName DJMLog -Times 1 -Exactly -ParameterFilter {
                $Uri -like '*/dataCollectionRules/dcr-fake/streams/Custom-Test_CL*'
            }
        }

        It 'maps UtcTimestamp to TimeGenerated in the POST body' {
            Send-DJMLogBuffer -Force
            Should -Invoke Invoke-RestMethod -ModuleName DJMLog -Times 1 -Exactly -ParameterFilter {
                $Body -match 'TimeGenerated'
            }
        }
    }

    Context 'Failure handling' {

        BeforeEach {
            Mock Invoke-RestMethod -ModuleName DJMLog { throw 'Simulated API failure' }
            InModuleScope DJMLog {
                $script:LogBuffer.Add(@{ UtcTimestamp = '2026-01-01T00:00:00Z'; Level = 'INFO'; Message = 'entry1'; CorrelationId = 'cid1' })
            }
        }

        It 'increments failure count on error' {
            Send-DJMLogBuffer -WarningAction SilentlyContinue
            InModuleScope DJMLog { $script:FlushFailureCount } | Should -Be 1
        }

        It 'preserves buffer entries on failure' {
            Send-DJMLogBuffer -WarningAction SilentlyContinue
            InModuleScope DJMLog { $script:LogBuffer.Count } | Should -Be 1
        }

        It 'trips circuit breaker at MaxFlushRetries threshold' {
            InModuleScope DJMLog { $script:FlushFailureCount = 2 }
            Send-DJMLogBuffer -WarningAction SilentlyContinue
            InModuleScope DJMLog { $script:AutoFlushDisabled } | Should -Be $true
        }

        It 'does not trip circuit breaker before threshold' {
            InModuleScope DJMLog { $script:FlushFailureCount = 0 }
            Send-DJMLogBuffer -WarningAction SilentlyContinue
            InModuleScope DJMLog { $script:AutoFlushDisabled } | Should -Be $false
        }
    }

    Context '-Force bypasses circuit breaker' {

        BeforeEach {
            Mock Invoke-RestMethod -ModuleName DJMLog { }
            InModuleScope DJMLog {
                $script:AutoFlushDisabled = $true
                $script:FlushFailureCount = 5
                $script:LogBuffer.Add(@{ UtcTimestamp = '2026-01-01T00:00:00Z'; Level = 'INFO'; Message = 'forced'; CorrelationId = 'cid' })
            }
        }

        It 'sends entries when -Force is used despite circuit breaker' {
            Send-DJMLogBuffer -Force
            InModuleScope DJMLog { $script:LogBuffer.Count } | Should -Be 0
        }

        It 'resets circuit breaker after successful forced flush' {
            Send-DJMLogBuffer -Force
            InModuleScope DJMLog { $script:AutoFlushDisabled } | Should -Be $false
            InModuleScope DJMLog { $script:FlushFailureCount } | Should -Be 0
        }
    }

    Context 'Batch chunking over 950 KB' {

        BeforeEach {
            Mock Invoke-RestMethod -ModuleName DJMLog { }
        }

        It 'splits large buffers into multiple REST calls when content exceeds 950 KB' {
            InModuleScope DJMLog {
                # 100 entries x ~12 KB each = ~1200 KB total.
                # At 500 KB threshold (old): ceil(1200/500) = 3 batches -> test asserts 2, so FAILS on old code.
                # At 950 KB threshold (new): ceil(1200/950) = 2 batches -> test asserts 2, PASSES on new code.
                $bigMessage = 'X' * 12000
                foreach ($i in 1..100) {
                    $script:LogBuffer.Add(@{
                        UtcTimestamp  = '2026-01-01T00:00:00Z'
                        Level         = 'INFO'
                        Message       = $bigMessage
                        CorrelationId = 'cid-chunk'
                    })
                }
            }

            Send-DJMLogBuffer

            Should -Invoke -CommandName Invoke-RestMethod -ModuleName DJMLog -Times 2 -Because 'buffer of ~1200 KB should be split into exactly 2 batches at the 950 KB threshold'
            InModuleScope DJMLog { $script:LogBuffer.Count } | Should -Be 0
        }

        It 'skips a single oversized record (>950 KB pre-compression), logs SelfLog entry, and sends remaining records' {
            InModuleScope DJMLog {
                $script:InternalErrors = [System.Collections.Generic.Queue[pscustomobject]]::new()

                # One record that is larger than 950 KB on its own
                $oversizedMessage = 'Y' * (960 * 1024)
                $script:LogBuffer.Add(@{
                    UtcTimestamp  = '2026-01-01T00:00:00Z'
                    Level         = 'INFO'
                    Message       = $oversizedMessage
                    CorrelationId = 'cid-oversized'
                })

                # A normal small record that should still be sent
                $script:LogBuffer.Add(@{
                    UtcTimestamp  = '2026-01-01T00:00:01Z'
                    Level         = 'INFO'
                    Message       = 'small entry'
                    CorrelationId = 'cid-small'
                })
            }

            Send-DJMLogBuffer -WarningAction SilentlyContinue

            # Buffer should be cleared (oversized dropped, small sent)
            InModuleScope DJMLog { $script:LogBuffer.Count } | Should -Be 0

            # SelfLog must have recorded the oversized-record rejection
            $diag = Get-DJMLogDiagnostics
            $oversizedError = @($diag.Errors) | Where-Object { $_.Message -match '950|oversized|too large|single.record|record.*size' }
            $oversizedError | Should -Not -BeNullOrEmpty

            # The small entry must have been sent (at least one call to Invoke-RestMethod)
            Should -Invoke Invoke-RestMethod -ModuleName DJMLog -Times 1 -Exactly -Because 'the small entry should be sent in its own batch'
        }

        It 'respects multi-byte UTF-8 byte count when computing chunk boundaries' {
            InModuleScope DJMLog {
                # CJK character U+4E2D is 3 bytes in UTF-8 — use it to build entries
                # of known byte size that straddle the 950 KB boundary.
                # Target: build 2 entries that together exceed 950 KB but each is under it.
                # Each entry message = ~500 KB of 3-byte chars (so char count != byte count).
                $cjkChar    = [char]0x4E2D    # 3 bytes in UTF-8
                # 500 KB / 3 bytes per char ≈ 170,667 chars per entry
                $charCount  = 170667
                $cjkMessage = [string]::new($cjkChar, $charCount)

                # Verify the byte count differs from char count (confirms multi-byte)
                $byteCount = [System.Text.Encoding]::UTF8.GetByteCount($cjkMessage)
                # byteCount should be ~3x charCount
                ($byteCount -gt $charCount * 2) | Should -BeTrue

                $script:LogBuffer.Add(@{
                    UtcTimestamp  = '2026-01-01T00:00:00Z'
                    Level         = 'INFO'
                    Message       = $cjkMessage
                    CorrelationId = 'cid-utf8-1'
                })
                $script:LogBuffer.Add(@{
                    UtcTimestamp  = '2026-01-01T00:00:01Z'
                    Level         = 'INFO'
                    Message       = $cjkMessage
                    CorrelationId = 'cid-utf8-2'
                })
            }

            Send-DJMLogBuffer

            # Two entries together exceed 950 KB (each ~500 KB of 3-byte chars plus JSON overhead),
            # so they must be split into separate batches — assert at least 2 REST calls
            Should -Invoke Invoke-RestMethod -ModuleName DJMLog -Times 2 -Because 'multi-byte UTF-8 byte accounting must split entries that together exceed 950 KB'
            InModuleScope DJMLog { $script:LogBuffer.Count } | Should -Be 0
        }
    }

    Context 'Circuit breaker half-open' {

        BeforeEach {
            InModuleScope DJMLog {
                $script:LogBuffer.Add(@{ UtcTimestamp = '2026-01-01T00:00:00Z'; Level = 'INFO'; Message = 'probe-entry'; CorrelationId = 'cid-probe' })
            }
        }

        It 'warns and skips the probe when HalfOpenAfterSeconds has not yet elapsed' {
            Mock Invoke-RestMethod -ModuleName DJMLog { }

            InModuleScope DJMLog {
                $script:AutoFlushDisabled    = $true
                $script:FlushFailureCount    = $script:MaxFlushRetries
                # Set AutoFlushOpenedAtUtc to only 10 seconds ago — well inside the 300-second window
                $script:AutoFlushOpenedAtUtc = [datetime]::UtcNow.AddSeconds(-10)
            }

            Send-DJMLogBuffer -WarningVariable w -WarningAction SilentlyContinue
            $w | Should -Not -BeNullOrEmpty
            # No REST call should have been attempted
            Should -Invoke Invoke-RestMethod -ModuleName DJMLog -Times 0 -Exactly
        }

        It 'attempts a single probe when HalfOpenAfterSeconds (300s) has elapsed' {
            Mock Invoke-RestMethod -ModuleName DJMLog { }

            InModuleScope DJMLog {
                $script:AutoFlushDisabled    = $true
                $script:FlushFailureCount    = $script:MaxFlushRetries
                # 301 seconds ago — past the half-open threshold
                $script:AutoFlushOpenedAtUtc = [datetime]::UtcNow.AddSeconds(-301)
            }

            Send-DJMLogBuffer -WarningAction SilentlyContinue

            # Exactly one probe call
            Should -Invoke Invoke-RestMethod -ModuleName DJMLog -Times 1 -Exactly
        }

        It 'closes the circuit on successful probe: AutoFlushDisabled -> false, FlushFailureCount -> 0' {
            Mock Invoke-RestMethod -ModuleName DJMLog { }

            InModuleScope DJMLog {
                $script:AutoFlushDisabled    = $true
                $script:FlushFailureCount    = $script:MaxFlushRetries
                $script:AutoFlushOpenedAtUtc = [datetime]::UtcNow.AddSeconds(-301)
            }

            Send-DJMLogBuffer -WarningAction SilentlyContinue

            InModuleScope DJMLog { $script:AutoFlushDisabled } | Should -Be $false
            InModuleScope DJMLog { $script:FlushFailureCount } | Should -Be 0
        }

        It 'keeps circuit open and refreshes AutoFlushOpenedAtUtc on probe failure' {
            Mock Invoke-RestMethod -ModuleName DJMLog { throw 'Simulated probe failure' }

            $openedAt = $null
            InModuleScope DJMLog {
                $script:AutoFlushDisabled    = $true
                $script:FlushFailureCount    = $script:MaxFlushRetries
                $script:AutoFlushOpenedAtUtc = [datetime]::UtcNow.AddSeconds(-301)
            }

            Send-DJMLogBuffer -WarningAction SilentlyContinue

            InModuleScope DJMLog { $script:AutoFlushDisabled } | Should -Be $true
            # AutoFlushOpenedAtUtc should have been refreshed to near now
            $refreshed = InModuleScope DJMLog { $script:AutoFlushOpenedAtUtc }
            $refreshed | Should -Not -BeNullOrEmpty
            ($refreshed -gt [datetime]::UtcNow.AddSeconds(-5)) | Should -BeTrue
        }
    }
}
