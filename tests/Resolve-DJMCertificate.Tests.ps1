BeforeAll {
    Import-Module "$PSScriptRoot\..\DJMLog.psd1" -Force
}

Describe 'Resolve-DJMCertificate' {

    Context 'Input validation' {

        It 'returns $null when neither -Thumbprint nor -Subject is supplied' {
            $result = InModuleScope DJMLog { Resolve-DJMCertificate }
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Thumbprint path' {

        It 'returns the matching certificate when valid' {
            $cert = [PSCustomObject]@{
                Subject       = 'CN=Probe'
                Thumbprint    = 'AA' * 20
                NotAfter      = [datetime]::UtcNow.AddDays(60)
                HasPrivateKey = $true
                PublicKey     = [PSCustomObject]@{ Key = [PSCustomObject]@{ KeySize = 2048 } }
            }
            Mock Get-Item -ModuleName DJMLog -ParameterFilter { $LiteralPath -like 'Cert:\*' } -MockWith { $cert }

            $result = InModuleScope DJMLog -ArgumentList ($cert.Thumbprint) {
                param ($tp)
                Resolve-DJMCertificate -Thumbprint $tp
            }
            $result.Thumbprint | Should -Be ('AA' * 20)
        }

        It 'returns $null when the certificate is expired' {
            $expired = [PSCustomObject]@{
                Subject       = 'CN=Expired'
                Thumbprint    = 'BB' * 20
                NotAfter      = [datetime]::UtcNow.AddDays(-1)
                HasPrivateKey = $true
                PublicKey     = [PSCustomObject]@{ Key = [PSCustomObject]@{ KeySize = 2048 } }
            }
            Mock Get-Item -ModuleName DJMLog -ParameterFilter { $LiteralPath -like 'Cert:\*' } -MockWith { $expired }

            $result = InModuleScope DJMLog { Resolve-DJMCertificate -Thumbprint ('BB' * 20) }
            $result | Should -BeNullOrEmpty
        }

        It 'returns $null when HasPrivateKey is false' {
            $noPk = [PSCustomObject]@{
                Subject       = 'CN=NoPK'
                Thumbprint    = 'CC' * 20
                NotAfter      = [datetime]::UtcNow.AddDays(60)
                HasPrivateKey = $false
                PublicKey     = [PSCustomObject]@{ Key = [PSCustomObject]@{ KeySize = 2048 } }
            }
            Mock Get-Item -ModuleName DJMLog -ParameterFilter { $LiteralPath -like 'Cert:\*' } -MockWith { $noPk }

            $result = InModuleScope DJMLog { Resolve-DJMCertificate -Thumbprint ('CC' * 20) }
            $result | Should -BeNullOrEmpty
        }

        It 'returns $null when key size is below MinKeySize' {
            $weak = [PSCustomObject]@{
                Subject       = 'CN=Weak'
                Thumbprint    = 'DD' * 20
                NotAfter      = [datetime]::UtcNow.AddDays(60)
                HasPrivateKey = $true
                PublicKey     = [PSCustomObject]@{ Key = [PSCustomObject]@{ KeySize = 1024 } }
            }
            Mock Get-Item -ModuleName DJMLog -ParameterFilter { $LiteralPath -like 'Cert:\*' } -MockWith { $weak }

            $result = InModuleScope DJMLog { Resolve-DJMCertificate -Thumbprint ('DD' * 20) -MinKeySize 2048 }
            $result | Should -BeNullOrEmpty
        }

        It 'returns $null when the thumbprint matches nothing' {
            Mock Get-Item -ModuleName DJMLog -ParameterFilter { $LiteralPath -like 'Cert:\*' } -MockWith { $null }

            $result = InModuleScope DJMLog { Resolve-DJMCertificate -Thumbprint ('EE' * 20) }
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Subject path' {

        It 'returns the candidate with the latest NotAfter' {
            $older = [PSCustomObject]@{
                Subject       = 'CN=DJMLog-Auth'
                Thumbprint    = 'AA' * 20
                NotAfter      = [datetime]::UtcNow.AddDays(30)
                HasPrivateKey = $true
                PublicKey     = [PSCustomObject]@{ Key = [PSCustomObject]@{ KeySize = 2048 } }
            }
            $newer = [PSCustomObject]@{
                Subject       = 'CN=DJMLog-Auth'
                Thumbprint    = 'BB' * 20
                NotAfter      = [datetime]::UtcNow.AddDays(180)
                HasPrivateKey = $true
                PublicKey     = [PSCustomObject]@{ Key = [PSCustomObject]@{ KeySize = 2048 } }
            }
            Mock Get-ChildItem -ModuleName DJMLog -ParameterFilter { $Path -like 'Cert:\*\My' } -MockWith {
                @($older, $newer)
            }

            $result = InModuleScope DJMLog { Resolve-DJMCertificate -Subject 'CN=DJMLog-Auth' }
            $result.Thumbprint | Should -Be ('BB' * 20)
        }

        It 'searches both LocalMachine\My and CurrentUser\My' {
            Mock Get-ChildItem -ModuleName DJMLog -ParameterFilter { $Path -like 'Cert:\*\My' } -MockWith { @() }

            InModuleScope DJMLog { Resolve-DJMCertificate -Subject 'CN=Nope' } | Out-Null
            Should -Invoke Get-ChildItem -ModuleName DJMLog -Times 2 -Because 'should enumerate LocalMachine\My then CurrentUser\My'
        }

        It 'ignores certs whose subject does not match exactly' {
            $other = [PSCustomObject]@{
                Subject       = 'CN=OtherCert'
                Thumbprint    = 'FF' * 20
                NotAfter      = [datetime]::UtcNow.AddDays(60)
                HasPrivateKey = $true
                PublicKey     = [PSCustomObject]@{ Key = [PSCustomObject]@{ KeySize = 2048 } }
            }
            Mock Get-ChildItem -ModuleName DJMLog -ParameterFilter { $Path -like 'Cert:\*\My' } -MockWith { @($other) }

            $result = InModuleScope DJMLog { Resolve-DJMCertificate -Subject 'CN=DJMLog-Auth' }
            $result | Should -BeNullOrEmpty
        }
    }
}
