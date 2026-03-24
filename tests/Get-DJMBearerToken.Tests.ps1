BeforeAll {
    Import-Module "$PSScriptRoot\..\DJMLog.psd1" -Force
}

Describe 'Get-DJMBearerToken' {

    BeforeEach {
        InModuleScope DJMLog {
            $script:BearerToken         = $null
            $script:BearerTokenExternal = $null
            $script:TokenExpiry         = [datetime]::MinValue
            $script:TenantId            = 'tenant-id'
            $script:AppId               = 'app-id'
            $script:AppSecret           = 'secret'
            $script:CertificateSubject  = $null
            $script:CertificateThumbprint = $null
            $script:CloudEnvironment    = 'GCCHigh'
        }
    }

    Context 'External token passthrough' {

        It 'returns external token when set' {
            InModuleScope DJMLog { $script:BearerTokenExternal = 'ext-token-123' }
            $result = InModuleScope DJMLog { Get-DJMBearerToken }
            $result | Should -Be 'ext-token-123'
        }

        It 'returns external token even when cached token exists' {
            InModuleScope DJMLog {
                $script:BearerTokenExternal = 'ext-token'
                $script:BearerToken = 'cached-token'
                $script:TokenExpiry = [datetime]::UtcNow.AddHours(1)
            }
            $result = InModuleScope DJMLog { Get-DJMBearerToken }
            $result | Should -Be 'ext-token'
        }
    }

    Context 'Cached token reuse' {

        It 'returns cached token when not expired' {
            InModuleScope DJMLog {
                $script:BearerToken = 'cached-valid'
                $script:TokenExpiry = [datetime]::UtcNow.AddMinutes(10)
            }
            $result = InModuleScope DJMLog { Get-DJMBearerToken }
            $result | Should -Be 'cached-valid'
        }

        It 'does not return cached token when expired' {
            Mock Invoke-RestMethod -ModuleName DJMLog {
                return @{ access_token = 'new-token'; expires_in = 3600 }
            }
            InModuleScope DJMLog {
                $script:BearerToken = 'expired-token'
                $script:TokenExpiry = [datetime]::UtcNow.AddMinutes(-1)
            }
            $result = InModuleScope DJMLog { Get-DJMBearerToken }
            $result | Should -Be 'new-token'
        }
    }

    Context 'Missing required configuration' {

        It 'returns $null and warns when TenantId is missing' {
            InModuleScope DJMLog { $script:TenantId = $null }
            $result = InModuleScope DJMLog { Get-DJMBearerToken } -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }

        It 'returns $null and warns when AppId is missing' {
            InModuleScope DJMLog { $script:AppId = $null }
            $result = InModuleScope DJMLog { Get-DJMBearerToken } -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }

        It 'returns $null when no auth method is configured' {
            InModuleScope DJMLog {
                $script:AppSecret = $null
                $script:CertificateSubject = $null
                $script:CertificateThumbprint = $null
            }
            $result = InModuleScope DJMLog { Get-DJMBearerToken } -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Unknown CloudEnvironment (BUG-2)' {

        It 'returns $null and warns for unknown cloud environment' {
            InModuleScope DJMLog { $script:CloudEnvironment = 'InvalidCloud' }
            $result = InModuleScope DJMLog { Get-DJMBearerToken } -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Client secret flow' {

        It 'acquires token via client secret and caches it' {
            Mock Invoke-RestMethod -ModuleName DJMLog {
                return @{ access_token = 'secret-token'; expires_in = 3600 }
            }
            $result = InModuleScope DJMLog { Get-DJMBearerToken }
            $result | Should -Be 'secret-token'
            InModuleScope DJMLog { $script:BearerToken } | Should -Be 'secret-token'
        }

        It 'sends correct grant_type and scope for GCCHigh' {
            Mock Invoke-RestMethod -ModuleName DJMLog -ParameterFilter {
                $Body.grant_type -eq 'client_credentials' -and
                $Body.scope -eq 'https://monitor.azure.us//.default'
            } -MockWith {
                return @{ access_token = 'gcc-token'; expires_in = 3600 }
            }
            $result = InModuleScope DJMLog { Get-DJMBearerToken }
            $result | Should -Be 'gcc-token'
        }
    }

    Context 'Malformed OAuth response (BUG-3)' {

        It 'returns $null when response has no access_token' {
            Mock Invoke-RestMethod -ModuleName DJMLog {
                return @{ expires_in = 3600 }
            }
            $result = InModuleScope DJMLog { Get-DJMBearerToken } -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }

        It 'returns $null when response has no expires_in' {
            Mock Invoke-RestMethod -ModuleName DJMLog {
                return @{ access_token = 'partial-token' }
            }
            $result = InModuleScope DJMLog { Get-DJMBearerToken } -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Token endpoint failure' {

        It 'returns $null when Invoke-RestMethod throws' {
            Mock Invoke-RestMethod -ModuleName DJMLog { throw 'Network error' }
            $result = InModuleScope DJMLog { Get-DJMBearerToken } -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Certificate thumbprint not found' {

        It 'returns $null when no cert matches the thumbprint' {
            InModuleScope DJMLog {
                $script:AppSecret = $null
                $script:CertificateThumbprint = 'AABBCCDD00112233AABBCCDD00112233AABBCCDD'
            }
            $result = InModuleScope DJMLog { Get-DJMBearerToken } -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }
}
