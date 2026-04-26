BeforeAll {
    Import-Module "$PSScriptRoot\..\DJMLog.psd1" -Force
}

AfterAll {
    Remove-Module DJMLog -Force -ErrorAction SilentlyContinue
}

# v2.0 — Send-DJMLogBuffer is now a back-compat wrapper over Flush-DJMLog.
# The v1.x test suite (Send-DJMLogBuffer.Tests.ps1.legacy in this directory)
# mocked Invoke-RestMethod in the main runspace; it cannot work against the
# v2.0 writer runspace which has its own session state. The retired tests are
# preserved alongside this file as documentation of the v1.x contract.

Describe 'Send-DJMLogBuffer (v2.0 back-compat wrapper)' {

    Context 'Precondition checks' {
        BeforeEach {
            InModuleScope DJMLog {
                $script:LogAnalyticsEnabled = $false
                $script:DcrEndpointUri      = $null
                $script:DcrImmutableId      = $null
                $script:DcrStreamName       = $null
            }
        }

        It 'warns and returns when LogAnalyticsEnabled is false' {
            $w = $null
            Send-DJMLogBuffer -WarningVariable w -WarningAction SilentlyContinue
            $w | Should -Not -BeNullOrEmpty
            ($w -join ' ') | Should -Match 'Log Analytics integration is not enabled'
        }

        It 'warns and returns when DcrEndpointUri is missing' {
            InModuleScope DJMLog {
                $script:LogAnalyticsEnabled = $true
                $script:DcrImmutableId      = 'dcr-x'
                $script:DcrStreamName       = 'Custom-x_CL'
            }
            $w = $null
            Send-DJMLogBuffer -WarningVariable w -WarningAction SilentlyContinue
            $w | Should -Not -BeNullOrEmpty
            ($w -join ' ') | Should -Match 'DcrEndpointUri'
        }

        It 'warns and returns when DcrImmutableId is missing' {
            InModuleScope DJMLog {
                $script:LogAnalyticsEnabled = $true
                $script:DcrEndpointUri      = 'https://x.azure.us'
                $script:DcrStreamName       = 'Custom-x_CL'
            }
            $w = $null
            Send-DJMLogBuffer -WarningVariable w -WarningAction SilentlyContinue
            $w | Should -Not -BeNullOrEmpty
            ($w -join ' ') | Should -Match 'DcrImmutableId'
        }
    }

    Context 'Forwards to Flush-DJMLog' {
        It 'returns void without error when LA is configured but no entries are buffered' {
            InModuleScope DJMLog {
                $script:LogAnalyticsEnabled = $true
                $script:DcrEndpointUri      = 'https://x.azure.us'
                $script:DcrImmutableId      = 'dcr-x'
                $script:DcrStreamName       = 'Custom-x_CL'
                # Reset breaker so Flush-DJMLog returns immediately
                $script:AutoFlushDisabled    = $false
                $script:AutoFlushOpenedAtUtc = $null
                if ($script:WriterShared) {
                    $script:WriterShared.AutoFlushDisabled    = $false
                    $script:WriterShared.AutoFlushOpenedAtUtc = $null
                }
            }
            { Send-DJMLogBuffer } | Should -Not -Throw
        }
    }
}
