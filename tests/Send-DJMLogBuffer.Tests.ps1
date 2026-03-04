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
            $script:LogBuffer               = [System.Collections.Generic.List[hashtable]]::new()
        }
    }

    AfterEach {
        InModuleScope DJMLog {
            $script:LogAnalyticsEnabled     = $false
            $script:LogBuffer               = [System.Collections.Generic.List[hashtable]]::new()
            $script:FlushFailureCount       = 0
            $script:AutoFlushDisabled       = $false
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
}
