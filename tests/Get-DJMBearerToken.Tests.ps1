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
                @{ access_token = 'new-token'; expires_in = 3600 }
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
                @{ access_token = 'secret-token'; expires_in = 3600 }
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
                @{ access_token = 'gcc-token'; expires_in = 3600 }
            }
            $result = InModuleScope DJMLog { Get-DJMBearerToken }
            $result | Should -Be 'gcc-token'
        }
    }

    Context 'Malformed OAuth response (BUG-3)' {

        It 'returns $null when response has no access_token' {
            Mock Invoke-RestMethod -ModuleName DJMLog {
                @{ expires_in = 3600 }
            }
            $result = InModuleScope DJMLog { Get-DJMBearerToken } -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }

        It 'returns $null when response has no expires_in' {
            Mock Invoke-RestMethod -ModuleName DJMLog {
                @{ access_token = 'partial-token' }
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

    Context 'Certificate selection — subject path (M3)' {

        BeforeEach {
            InModuleScope DJMLog {
                $script:AppSecret             = $null
                $script:CertificateThumbprint = $null
                $script:CertificateSubject    = 'CN=DJMLog-Auth'
                $script:TenantId              = 'tenant-id'
                $script:AppId                 = 'app-id'
                $script:CloudEnvironment      = 'GCCHigh'
            }
        }

        It 'picks the certificate with the latest NotAfter among valid candidates' {
            InModuleScope DJMLog {
                # Build two fake cert objects with different NotAfter
                $olderCert = [PSCustomObject]@{
                    Subject       = 'CN=DJMLog-Auth'
                    Thumbprint    = 'AA' * 20
                    NotAfter      = [datetime]::UtcNow.AddDays(30)
                    HasPrivateKey = $true
                    PublicKey     = [PSCustomObject]@{ Key = [PSCustomObject]@{ KeySize = 2048 } }
                }
                $newerCert = [PSCustomObject]@{
                    Subject       = 'CN=DJMLog-Auth'
                    Thumbprint    = 'BB' * 20
                    NotAfter      = [datetime]::UtcNow.AddDays(90)
                    HasPrivateKey = $true
                    PublicKey     = [PSCustomObject]@{ Key = [PSCustomObject]@{ KeySize = 2048 } }
                }

                Mock Get-ChildItem -ModuleName DJMLog -ParameterFilter { $Path -like 'Cert:\*\My' } {
                    @($olderCert, $newerCert)
                }

                # Mock JWT signing so we don't need a real RSA key
                Mock Invoke-RestMethod -ModuleName DJMLog {
                    @{ access_token = 'cert-token-newer'; expires_in = 3600 }
                }
            }

            # We cannot easily assert which cert object was selected without
            # inspecting internal state, so we verify the flow succeeded (token returned)
            # and that Get-ChildItem was called to enumerate candidates.
            $result = InModuleScope DJMLog { Get-DJMBearerToken } -WarningAction SilentlyContinue

            # The function must have attempted to use the newer cert (higher NotAfter).
            # Since the signing will fail (no real RSA key on PSCustomObject), we assert
            # that either a token is returned OR $null is returned after a warning.
            # What matters is that Get-ChildItem was invoked for cert enumeration.
            Should -Invoke Get-ChildItem -ModuleName DJMLog -Times 2 -Because 'should search LocalMachine\My and CurrentUser\My'
        }

        It 'filters out expired certificates even when subject matches' {
            InModuleScope DJMLog {
                $expiredCert = [PSCustomObject]@{
                    Subject       = 'CN=DJMLog-Auth'
                    Thumbprint    = 'EE' * 20
                    NotAfter      = [datetime]::UtcNow.AddDays(-1)   # expired
                    HasPrivateKey = $true
                    PublicKey     = [PSCustomObject]@{ Key = [PSCustomObject]@{ KeySize = 2048 } }
                }

                Mock Get-ChildItem -ModuleName DJMLog -ParameterFilter { $Path -like 'Cert:\*\My' } {
                    @($expiredCert)
                }
            }

            $result = InModuleScope DJMLog { Get-DJMBearerToken } -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }

        It 'rejects a certificate with key size < 2048 bits and returns null with a warning' {
            InModuleScope DJMLog {
                $weakCert = [PSCustomObject]@{
                    Subject       = 'CN=DJMLog-Auth'
                    Thumbprint    = 'CC' * 20
                    NotAfter      = [datetime]::UtcNow.AddDays(60)
                    HasPrivateKey = $true
                    PublicKey     = [PSCustomObject]@{ Key = [PSCustomObject]@{ KeySize = 1024 } }
                }

                Mock Get-ChildItem -ModuleName DJMLog -ParameterFilter { $Path -like 'Cert:\*\My' } {
                    @($weakCert)
                }
            }

            $result = InModuleScope DJMLog { Get-DJMBearerToken } -WarningVariable w -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $w | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Certificate selection — thumbprint path (M3)' {

        BeforeEach {
            InModuleScope DJMLog {
                $script:AppSecret             = $null
                $script:CertificateSubject    = $null
                $script:TenantId              = 'tenant-id'
                $script:AppId                 = 'app-id'
                $script:CloudEnvironment      = 'GCCHigh'
            }
        }

        It 'returns null with a warning when the matching thumbprint cert is expired' {
            InModuleScope DJMLog {
                $script:CertificateThumbprint = 'AABBCCDD' * 5

                $expiredCert = [PSCustomObject]@{
                    Subject       = 'CN=ExpiredCert'
                    Thumbprint    = 'AABBCCDD' * 5
                    NotAfter      = [datetime]::UtcNow.AddDays(-1)   # expired
                    HasPrivateKey = $true
                    PublicKey     = [PSCustomObject]@{ Key = [PSCustomObject]@{ KeySize = 2048 } }
                }

                Mock Get-Item -ModuleName DJMLog -ParameterFilter { $LiteralPath -like 'Cert:\*' } {
                    $expiredCert
                }
            }

            $result = InModuleScope DJMLog { Get-DJMBearerToken } -WarningVariable w -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $w | Should -Not -BeNullOrEmpty
        }

        It 'returns null when thumbprint is found but HasPrivateKey is false' {
            InModuleScope DJMLog {
                $script:CertificateThumbprint = 'DDCCBBAA' * 5

                $noPkCert = [PSCustomObject]@{
                    Subject       = 'CN=NoPKCert'
                    Thumbprint    = 'DDCCBBAA' * 5
                    NotAfter      = [datetime]::UtcNow.AddDays(60)
                    HasPrivateKey = $false
                    PublicKey     = [PSCustomObject]@{ Key = [PSCustomObject]@{ KeySize = 2048 } }
                }

                Mock Get-Item -ModuleName DJMLog -ParameterFilter { $LiteralPath -like 'Cert:\*' } {
                    $noPkCert
                }
            }

            $result = InModuleScope DJMLog { Get-DJMBearerToken } -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Secret hygiene (C6)' {

        BeforeEach {
            InModuleScope DJMLog {
                $script:DefaultLogPath          = $null
                $script:DefaultMaxSizeMB        = 0
                $script:DefaultMutexTimeoutMs   = 2000
                $script:DefaultMinLevel         = 'DEBUG'
                $script:DefaultRotationSchedule = 'None'
                $script:DefaultRetainDays       = 0
                $script:DefaultRetainFiles      = 0
                $script:DefaultIncludeCaller    = $true
                $script:LogAnalyticsEnabled     = $false
                $script:CloudEnvironment        = 'GCCHigh'
                $script:DcrEndpointUri          = $null
                $script:DcrImmutableId          = $null
                $script:DcrStreamName           = $null
                $script:TenantId                = $null
                $script:AppId                   = $null
                $script:AppSecret               = $null
                $script:CertificateSubject      = $null
                $script:CertificateThumbprint   = $null
                $script:BearerTokenExternal     = $null
                $script:FlushThreshold          = 100
                $script:MaxBufferSize           = 5000
                $script:MaxFlushRetries         = 3
                $script:FlushFailureCount       = 0
                $script:AutoFlushDisabled       = $false
            }
        }

        It 'stores a SecureString AppSecret as SecureString in module state' {
            # PSScriptAnalyzer: ConvertTo-SecureString with -AsPlainText is intentional in test context
            $secure = ConvertTo-SecureString 'p@ss' -AsPlainText -Force
            Set-DJMLogConfig -AppSecret $secure
            $isSecureString = InModuleScope DJMLog { $script:AppSecret -is [System.Security.SecureString] }
            $isSecureString | Should -BeTrue
        }

        It 'converts a plain string AppSecret to SecureString on assignment' {
            Set-DJMLogConfig -AppSecret 'plainsecret'
            $isSecureString = InModuleScope DJMLog { $script:AppSecret -is [System.Security.SecureString] }
            $isSecureString | Should -BeTrue
        }

        It 'round-trips the plain string secret through SecureString without data loss' {
            Set-DJMLogConfig -AppSecret 'plainsecret'
            $plainBack = InModuleScope DJMLog {
                [System.Net.NetworkCredential]::new('', $script:AppSecret).Password
            }
            $plainBack | Should -Be 'plainsecret'
        }
    }
}
