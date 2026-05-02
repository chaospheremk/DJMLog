BeforeAll {
    Import-Module "$PSScriptRoot\..\DJMLog.psd1" -Force
}

Describe 'Get-DJMManagedIdentityToken' {

    Context 'IMDS request shape' {

        It 'targets the IMDS metadata endpoint' {
            Mock Invoke-DJMRestMethodWithRetry -ModuleName DJMLog -ParameterFilter {
                $Uri -like 'http://169.254.169.254/metadata/identity/oauth2/token*'
            } -MockWith {
                @{ access_token = 'mi-token'; expires_in = 3600 }
            }
            $result = InModuleScope DJMLog {
                Get-DJMManagedIdentityToken -Resource 'https://monitor.azure.us'
            }
            $result.access_token | Should -Be 'mi-token'
        }

        It 'sends Metadata: true header' {
            Mock Invoke-DJMRestMethodWithRetry -ModuleName DJMLog -ParameterFilter {
                $Headers['Metadata'] -eq 'true'
            } -MockWith {
                @{ access_token = 'mi-token'; expires_in = 3600 }
            }
            InModuleScope DJMLog {
                Get-DJMManagedIdentityToken -Resource 'https://monitor.azure.us'
            }
            Should -Invoke Invoke-DJMRestMethodWithRetry -ModuleName DJMLog -Times 1 -Exactly -ParameterFilter {
                $Headers['Metadata'] -eq 'true'
            }
        }

        It 'uses GET method' {
            Mock Invoke-DJMRestMethodWithRetry -ModuleName DJMLog {
                @{ access_token = 'mi-token'; expires_in = 3600 }
            }
            InModuleScope DJMLog {
                Get-DJMManagedIdentityToken -Resource 'https://monitor.azure.us'
            }
            Should -Invoke Invoke-DJMRestMethodWithRetry -ModuleName DJMLog -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'GET'
            }
        }

        It 'includes api-version=2018-02-01 query parameter' {
            Mock Invoke-DJMRestMethodWithRetry -ModuleName DJMLog -ParameterFilter {
                $Uri -match 'api-version=2018-02-01'
            } -MockWith {
                @{ access_token = 'mi-token'; expires_in = 3600 }
            }
            InModuleScope DJMLog {
                Get-DJMManagedIdentityToken -Resource 'https://monitor.azure.us'
            }
            Should -Invoke Invoke-DJMRestMethodWithRetry -ModuleName DJMLog -Times 1 -Exactly -ParameterFilter {
                $Uri -match 'api-version=2018-02-01'
            }
        }

        It 'URL-encodes the resource query parameter' {
            Mock Invoke-DJMRestMethodWithRetry -ModuleName DJMLog -ParameterFilter {
                $Uri -match 'resource=https%3A%2F%2Fmonitor\.azure\.us'
            } -MockWith {
                @{ access_token = 'mi-token'; expires_in = 3600 }
            }
            InModuleScope DJMLog {
                Get-DJMManagedIdentityToken -Resource 'https://monitor.azure.us'
            }
            Should -Invoke Invoke-DJMRestMethodWithRetry -ModuleName DJMLog -Times 1 -Exactly
        }
    }

    Context 'User-assigned managed identity' {

        It 'appends &client_id when -ClientId is supplied' {
            Mock Invoke-DJMRestMethodWithRetry -ModuleName DJMLog -ParameterFilter {
                $Uri -match 'client_id=user-mi-id'
            } -MockWith {
                @{ access_token = 'user-mi-token'; expires_in = 3600 }
            }
            $result = InModuleScope DJMLog {
                Get-DJMManagedIdentityToken -Resource 'https://monitor.azure.us' -ClientId 'user-mi-id'
            }
            $result.access_token | Should -Be 'user-mi-token'
        }

        It 'omits client_id when -ClientId is not supplied (system-assigned MI)' {
            Mock Invoke-DJMRestMethodWithRetry -ModuleName DJMLog -ParameterFilter {
                $Uri -notmatch 'client_id='
            } -MockWith {
                @{ access_token = 'sys-mi-token'; expires_in = 3600 }
            }
            $result = InModuleScope DJMLog {
                Get-DJMManagedIdentityToken -Resource 'https://monitor.azure.us'
            }
            $result.access_token | Should -Be 'sys-mi-token'
        }

        It 'omits client_id when -ClientId is empty string' {
            Mock Invoke-DJMRestMethodWithRetry -ModuleName DJMLog -ParameterFilter {
                $Uri -notmatch 'client_id='
            } -MockWith {
                @{ access_token = 'sys-mi-token'; expires_in = 3600 }
            }
            $result = InModuleScope DJMLog {
                Get-DJMManagedIdentityToken -Resource 'https://monitor.azure.us' -ClientId ''
            }
            $result.access_token | Should -Be 'sys-mi-token'
        }
    }

    Context 'Error propagation' {

        It 'rethrows when IMDS returns a non-2xx response' {
            Mock Invoke-DJMRestMethodWithRetry -ModuleName DJMLog { throw 'IMDS unreachable' }
            { InModuleScope DJMLog {
                Get-DJMManagedIdentityToken -Resource 'https://monitor.azure.us'
            } } | Should -Throw '*IMDS unreachable*'
        }
    }
}
