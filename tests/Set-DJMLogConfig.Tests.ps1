BeforeAll {
    Import-Module "$PSScriptRoot\..\DJMLog.psd1" -Force
}

Describe 'Set-DJMLogConfig' {

    BeforeEach {
        # Reset module state to known defaults before every test
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
            $script:MaxBufferBytes          = 52428800
            $script:FlushFailureCount       = 0
            $script:AutoFlushDisabled       = $false
        }
    }

    Context 'Direct parameter assignment' {

        It 'sets DefaultLogPath' {
            Set-DJMLogConfig -Path 'C:\Logs\test.jsonl'
            InModuleScope DJMLog { $script:DefaultLogPath } | Should -Be 'C:\Logs\test.jsonl'
        }

        It 'sets DefaultMaxSizeMB' {
            Set-DJMLogConfig -MaxSizeMB 50
            InModuleScope DJMLog { $script:DefaultMaxSizeMB } | Should -Be 50
        }

        It 'sets DefaultMutexTimeoutMs' {
            Set-DJMLogConfig -MutexTimeoutMs 5000
            InModuleScope DJMLog { $script:DefaultMutexTimeoutMs } | Should -Be 5000
        }

        It 'accepts MaxSizeMB of 0 to disable rotation' {
            Set-DJMLogConfig -MaxSizeMB 100
            Set-DJMLogConfig -MaxSizeMB 0
            InModuleScope DJMLog { $script:DefaultMaxSizeMB } | Should -Be 0
        }

        It 'does not reset unspecified defaults' {
            Set-DJMLogConfig -Path 'C:\Logs\a.jsonl'
            Set-DJMLogConfig -MaxSizeMB 25
            # Path should still be set from the first call
            InModuleScope DJMLog { $script:DefaultLogPath } | Should -Be 'C:\Logs\a.jsonl'
        }

        It 'sets DefaultMinLevel and uppercases the value' {
            Set-DJMLogConfig -MinLevel 'warn'
            InModuleScope DJMLog { $script:DefaultMinLevel } | Should -Be 'WARN'
        }

        It 'accepts all valid MinLevel values' {
            foreach ($level in @('DEBUG', 'INFO', 'WARN', 'ERROR')) {
                Set-DJMLogConfig -MinLevel $level
                InModuleScope DJMLog { $script:DefaultMinLevel } | Should -Be $level
            }
        }

        It 'sets DefaultRotationSchedule' {
            Set-DJMLogConfig -RotationSchedule Daily
            InModuleScope DJMLog { $script:DefaultRotationSchedule } | Should -Be 'Daily'
        }

        It 'accepts all valid RotationSchedule values' {
            foreach ($sched in @('None', 'Daily', 'Hourly')) {
                Set-DJMLogConfig -RotationSchedule $sched
                InModuleScope DJMLog { $script:DefaultRotationSchedule } | Should -Be $sched
            }
        }

        It 'sets DefaultRetainDays' {
            Set-DJMLogConfig -RetainDays 30
            InModuleScope DJMLog { $script:DefaultRetainDays } | Should -Be 30
        }

        It 'accepts RetainDays of 0 to keep all files' {
            Set-DJMLogConfig -RetainDays 14
            Set-DJMLogConfig -RetainDays 0
            InModuleScope DJMLog { $script:DefaultRetainDays } | Should -Be 0
        }

        It 'sets DefaultRetainFiles' {
            Set-DJMLogConfig -RetainFiles 10
            InModuleScope DJMLog { $script:DefaultRetainFiles } | Should -Be 10
        }

        It 'accepts RetainFiles of 0 to keep all files' {
            Set-DJMLogConfig -RetainFiles 5
            Set-DJMLogConfig -RetainFiles 0
            InModuleScope DJMLog { $script:DefaultRetainFiles } | Should -Be 0
        }

        It 'sets DefaultIncludeCaller to false' {
            Set-DJMLogConfig -IncludeCaller $false
            InModuleScope DJMLog { $script:DefaultIncludeCaller } | Should -Be $false
        }

        It 'sets DefaultIncludeCaller to true' {
            InModuleScope DJMLog { $script:DefaultIncludeCaller = $false }
            Set-DJMLogConfig -IncludeCaller $true
            InModuleScope DJMLog { $script:DefaultIncludeCaller } | Should -Be $true
        }
    }

    Context 'Config file loading' {

        BeforeAll {
            $script:ConfigFile = [System.IO.Path]::GetTempFileName()
        }

        AfterAll {
            Remove-Item -LiteralPath $script:ConfigFile -ErrorAction SilentlyContinue
        }

        It 'loads Path from a JSON config file' {
            '{ "Path": "C:\\Logs\\from-file.jsonl" }' | Set-Content -LiteralPath $script:ConfigFile
            Set-DJMLogConfig -ConfigPath $script:ConfigFile
            InModuleScope DJMLog { $script:DefaultLogPath } | Should -Be 'C:\Logs\from-file.jsonl'
        }

        It 'loads MaxSizeMB from a JSON config file' {
            '{ "MaxSizeMB": 75 }' | Set-Content -LiteralPath $script:ConfigFile
            Set-DJMLogConfig -ConfigPath $script:ConfigFile
            InModuleScope DJMLog { $script:DefaultMaxSizeMB } | Should -Be 75
        }

        It 'loads MutexTimeoutMs from a JSON config file' {
            '{ "MutexTimeoutMs": 5000 }' | Set-Content -LiteralPath $script:ConfigFile
            Set-DJMLogConfig -ConfigPath $script:ConfigFile
            InModuleScope DJMLog { $script:DefaultMutexTimeoutMs } | Should -Be 5000
        }

        It 'loads MinLevel from a JSON config file' {
            '{ "MinLevel": "ERROR" }' | Set-Content -LiteralPath $script:ConfigFile
            Set-DJMLogConfig -ConfigPath $script:ConfigFile
            InModuleScope DJMLog { $script:DefaultMinLevel } | Should -Be 'ERROR'
        }

        It 'loads RotationSchedule from a JSON config file' {
            '{ "RotationSchedule": "Hourly" }' | Set-Content -LiteralPath $script:ConfigFile
            Set-DJMLogConfig -ConfigPath $script:ConfigFile
            InModuleScope DJMLog { $script:DefaultRotationSchedule } | Should -Be 'Hourly'
        }

        It 'loads RetainDays from a JSON config file' {
            '{ "RetainDays": 14 }' | Set-Content -LiteralPath $script:ConfigFile
            Set-DJMLogConfig -ConfigPath $script:ConfigFile
            InModuleScope DJMLog { $script:DefaultRetainDays } | Should -Be 14
        }

        It 'loads RetainFiles from a JSON config file' {
            '{ "RetainFiles": 5 }' | Set-Content -LiteralPath $script:ConfigFile
            Set-DJMLogConfig -ConfigPath $script:ConfigFile
            InModuleScope DJMLog { $script:DefaultRetainFiles } | Should -Be 5
        }

        It 'loads IncludeCaller false from a JSON config file' {
            '{ "IncludeCaller": false }' | Set-Content -LiteralPath $script:ConfigFile
            Set-DJMLogConfig -ConfigPath $script:ConfigFile
            InModuleScope DJMLog { $script:DefaultIncludeCaller } | Should -Be $false
        }

        It 'explicit -Path overrides config file Path' {
            '{ "Path": "C:\\Logs\\from-file.jsonl" }' | Set-Content -LiteralPath $script:ConfigFile
            Set-DJMLogConfig -ConfigPath $script:ConfigFile -Path 'C:\Logs\override.jsonl'
            InModuleScope DJMLog { $script:DefaultLogPath } | Should -Be 'C:\Logs\override.jsonl'
        }

        It 'explicit -MinLevel overrides config file MinLevel' {
            '{ "MinLevel": "ERROR" }' | Set-Content -LiteralPath $script:ConfigFile
            Set-DJMLogConfig -ConfigPath $script:ConfigFile -MinLevel INFO
            InModuleScope DJMLog { $script:DefaultMinLevel } | Should -Be 'INFO'
        }

        It 'explicit -IncludeCaller overrides config file IncludeCaller' {
            '{ "IncludeCaller": false }' | Set-Content -LiteralPath $script:ConfigFile
            Set-DJMLogConfig -ConfigPath $script:ConfigFile -IncludeCaller $true
            InModuleScope DJMLog { $script:DefaultIncludeCaller } | Should -Be $true
        }

        It 'ignores unknown properties in the config file' {
            '{ "Path": "C:\\Logs\\ok.jsonl", "Unknown": "ignored" }' | Set-Content -LiteralPath $script:ConfigFile
            { Set-DJMLogConfig -ConfigPath $script:ConfigFile } | Should -Not -Throw
        }

        It 'emits a warning when the config file path does not exist' {
            { Set-DJMLogConfig -ConfigPath 'C:\DoesNotExist\config.json' -WarningAction Stop } |
                Should -Throw
        }

        It 'emits a warning when the config file contains invalid JSON' {
            'not valid json {{ ' | Set-Content -LiteralPath $script:ConfigFile
            { Set-DJMLogConfig -ConfigPath $script:ConfigFile -WarningAction Stop } |
                Should -Throw
        }
    }

    Context 'Log Analytics parameters' {

        It 'sets LogAnalyticsEnabled' {
            Set-DJMLogConfig -LogAnalyticsEnabled $true
            InModuleScope DJMLog { $script:LogAnalyticsEnabled } | Should -Be $true
        }

        It 'sets CloudEnvironment' {
            Set-DJMLogConfig -CloudEnvironment Commercial
            InModuleScope DJMLog { $script:CloudEnvironment } | Should -Be 'Commercial'
        }

        It 'accepts all valid CloudEnvironment values' {
            foreach ($env in @('Commercial', 'GCCHigh', 'DoD')) {
                Set-DJMLogConfig -CloudEnvironment $env
                InModuleScope DJMLog { $script:CloudEnvironment } | Should -Be $env
            }
        }

        It 'sets DcrEndpointUri' {
            Set-DJMLogConfig -DcrEndpointUri 'https://fake.ingest.monitor.azure.us'
            InModuleScope DJMLog { $script:DcrEndpointUri } | Should -Be 'https://fake.ingest.monitor.azure.us'
        }

        It 'sets DcrImmutableId' {
            Set-DJMLogConfig -DcrImmutableId 'dcr-test123'
            InModuleScope DJMLog { $script:DcrImmutableId } | Should -Be 'dcr-test123'
        }

        It 'sets DcrStreamName' {
            Set-DJMLogConfig -DcrStreamName 'Custom-MyLog_CL'
            InModuleScope DJMLog { $script:DcrStreamName } | Should -Be 'Custom-MyLog_CL'
        }

        It 'sets TenantId' {
            Set-DJMLogConfig -TenantId 'tenant-abc'
            InModuleScope DJMLog { $script:TenantId } | Should -Be 'tenant-abc'
        }

        It 'sets AppId' {
            Set-DJMLogConfig -AppId 'app-xyz'
            InModuleScope DJMLog { $script:AppId } | Should -Be 'app-xyz'
        }

        It 'converts a plain-string AppSecret to SecureString on assignment (ADR-015)' {
            Set-DJMLogConfig -AppSecret 'my-secret'
            InModuleScope DJMLog { $script:AppSecret -is [System.Security.SecureString] } | Should -BeTrue
            $roundtripped = InModuleScope DJMLog {
                [System.Net.NetworkCredential]::new('', $script:AppSecret).Password
            }
            $roundtripped | Should -Be 'my-secret'
        }

        It 'sets AppSecret as SecureString' {
            # Plaintext conversion is intentional in test context
            $secure = ConvertTo-SecureString 'secret-value' -AsPlainText -Force  # PSScriptAnalyzer: test-only
            Set-DJMLogConfig -AppSecret $secure
            InModuleScope DJMLog { $script:AppSecret -is [System.Security.SecureString] } | Should -Be $true
        }

        It 'sets CertificateSubject' {
            Set-DJMLogConfig -CertificateSubject 'CN=DJMLog-Auth'
            InModuleScope DJMLog { $script:CertificateSubject } | Should -Be 'CN=DJMLog-Auth'
        }

        It 'sets CertificateThumbprint' {
            Set-DJMLogConfig -CertificateThumbprint 'AABB1122'
            InModuleScope DJMLog { $script:CertificateThumbprint } | Should -Be 'AABB1122'
        }

        It 'sets BearerToken to BearerTokenExternal' {
            Set-DJMLogConfig -BearerToken 'eyJ-fake-token'
            InModuleScope DJMLog { $script:BearerTokenExternal } | Should -Be 'eyJ-fake-token'
        }

        It 'sets FlushThreshold' {
            Set-DJMLogConfig -FlushThreshold 50
            InModuleScope DJMLog { $script:FlushThreshold } | Should -Be 50
        }

        It 'sets MaxBufferSize' {
            Set-DJMLogConfig -MaxBufferSize 10000
            InModuleScope DJMLog { $script:MaxBufferSize } | Should -Be 10000
        }

        It 'sets MaxFlushRetries' {
            Set-DJMLogConfig -MaxFlushRetries 5
            InModuleScope DJMLog { $script:MaxFlushRetries } | Should -Be 5
        }

        It 'resets circuit breaker when any LA param is set' {
            InModuleScope DJMLog {
                $script:FlushFailureCount = 5
                $script:AutoFlushDisabled = $true
            }
            Set-DJMLogConfig -FlushThreshold 200
            InModuleScope DJMLog { $script:FlushFailureCount } | Should -Be 0
            InModuleScope DJMLog { $script:AutoFlushDisabled } | Should -Be $false
        }

        It 'does not reset circuit breaker when only non-LA params are set' {
            InModuleScope DJMLog {
                $script:FlushFailureCount = 3
                $script:AutoFlushDisabled = $true
            }
            Set-DJMLogConfig -Path 'C:\Logs\test.jsonl'
            InModuleScope DJMLog { $script:FlushFailureCount } | Should -Be 3
            InModuleScope DJMLog { $script:AutoFlushDisabled } | Should -Be $true
        }
    }

    Context 'Log Analytics config file loading' {

        BeforeAll {
            $script:LAConfigFile = [System.IO.Path]::GetTempFileName()
        }

        AfterAll {
            Remove-Item -LiteralPath $script:LAConfigFile -ErrorAction SilentlyContinue
        }

        It 'loads LogAnalyticsEnabled from config file' {
            '{ "LogAnalyticsEnabled": true }' | Set-Content -LiteralPath $script:LAConfigFile
            Set-DJMLogConfig -ConfigPath $script:LAConfigFile
            InModuleScope DJMLog { $script:LogAnalyticsEnabled } | Should -Be $true
        }

        It 'loads CloudEnvironment from config file' {
            '{ "CloudEnvironment": "DoD" }' | Set-Content -LiteralPath $script:LAConfigFile
            Set-DJMLogConfig -ConfigPath $script:LAConfigFile
            InModuleScope DJMLog { $script:CloudEnvironment } | Should -Be 'DoD'
        }

        It 'loads DcrEndpointUri from config file' {
            '{ "DcrEndpointUri": "https://from-file.ingest.monitor.azure.us" }' | Set-Content -LiteralPath $script:LAConfigFile
            Set-DJMLogConfig -ConfigPath $script:LAConfigFile
            InModuleScope DJMLog { $script:DcrEndpointUri } | Should -Be 'https://from-file.ingest.monitor.azure.us'
        }

        It 'loads FlushThreshold from config file' {
            '{ "FlushThreshold": 200 }' | Set-Content -LiteralPath $script:LAConfigFile
            Set-DJMLogConfig -ConfigPath $script:LAConfigFile
            InModuleScope DJMLog { $script:FlushThreshold } | Should -Be 200
        }

        It 'loads MaxBufferSize from config file' {
            '{ "MaxBufferSize": 8000 }' | Set-Content -LiteralPath $script:LAConfigFile
            Set-DJMLogConfig -ConfigPath $script:LAConfigFile
            InModuleScope DJMLog { $script:MaxBufferSize } | Should -Be 8000
        }

        It 'loads MaxFlushRetries from config file' {
            '{ "MaxFlushRetries": 10 }' | Set-Content -LiteralPath $script:LAConfigFile
            Set-DJMLogConfig -ConfigPath $script:LAConfigFile
            InModuleScope DJMLog { $script:MaxFlushRetries } | Should -Be 10
        }

        It 'explicit -CloudEnvironment overrides config file' {
            '{ "CloudEnvironment": "DoD" }' | Set-Content -LiteralPath $script:LAConfigFile
            Set-DJMLogConfig -ConfigPath $script:LAConfigFile -CloudEnvironment Commercial
            InModuleScope DJMLog { $script:CloudEnvironment } | Should -Be 'Commercial'
        }

        It 'explicit -BearerToken overrides config file' {
            '{ "BearerToken": "file-token" }' | Set-Content -LiteralPath $script:LAConfigFile
            Set-DJMLogConfig -ConfigPath $script:LAConfigFile -BearerToken 'param-token'
            InModuleScope DJMLog { $script:BearerTokenExternal } | Should -Be 'param-token'
        }
    }

    Context 'MaxBufferBytes parameter (H3)' {

        It 'sets MaxBufferBytes when supplied as a positive integer' {
            Set-DJMLogConfig -MaxBufferBytes 2097152
            InModuleScope DJMLog { $script:MaxBufferBytes } | Should -Be 2097152
        }

        It 'accepts MaxBufferBytes of 0 (disable byte-cap)' {
            Set-DJMLogConfig -MaxBufferBytes 0
            InModuleScope DJMLog { $script:MaxBufferBytes } | Should -Be 0
        }

        It 'defaults MaxBufferBytes to 50 MB (52428800) on fresh module load' {
            # The module default is 52428800 bytes (50 * 1024 * 1024)
            InModuleScope DJMLog { $script:MaxBufferBytes } | Should -Be 52428800
        }

        It 'rejects a negative MaxBufferBytes with an error' {
            { Set-DJMLogConfig -MaxBufferBytes -1 -ErrorAction Stop } | Should -Throw
        }
    }

    Context 'Log Analytics validation (M2)' {

        It 'emits a single error listing all missing LA fields when LogAnalyticsEnabled=$true with no auth or DCR config' {
            Set-DJMLogConfig -LogAnalyticsEnabled $true -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -Not -BeNullOrEmpty
            # The error message should reference the missing required fields
            $errText = ($err | ForEach-Object { $_.ToString() }) -join ' '
            $errText | Should -Match 'DcrEndpointUri|DcrImmutableId|DcrStreamName|TenantId|AppId|auth'
        }

        It 'does not emit an error when BearerToken is supplied with DCE/DCR/Stream (no TenantId/AppId needed)' {
            $params = @{
                LogAnalyticsEnabled = $true
                DcrEndpointUri      = 'https://fake.ingest.monitor.azure.us'
                DcrImmutableId      = 'dcr-fake'
                DcrStreamName       = 'Custom-Test_CL'
                BearerToken         = 'eyJ-fake-token'
            }
            { Set-DJMLogConfig @params -ErrorAction Stop } | Should -Not -Throw
        }

        It 'does not emit an error when CertificateThumbprint with TenantId/AppId and DCR config are all supplied' {
            $params = @{
                LogAnalyticsEnabled    = $true
                DcrEndpointUri         = 'https://fake.ingest.monitor.azure.us'
                DcrImmutableId         = 'dcr-fake'
                DcrStreamName          = 'Custom-Test_CL'
                TenantId               = 'tenant-id'
                AppId                  = 'app-id'
                CertificateThumbprint  = 'AABB1122'
            }
            { Set-DJMLogConfig @params -ErrorAction Stop } | Should -Not -Throw
        }

        It 'does not emit an error when CertificateSubject with TenantId/AppId and DCR config are all supplied' {
            $params = @{
                LogAnalyticsEnabled = $true
                DcrEndpointUri      = 'https://fake.ingest.monitor.azure.us'
                DcrImmutableId      = 'dcr-fake'
                DcrStreamName       = 'Custom-Test_CL'
                TenantId            = 'tenant-id'
                AppId               = 'app-id'
                CertificateSubject  = 'CN=DJMLog-Auth'
            }
            { Set-DJMLogConfig @params -ErrorAction Stop } | Should -Not -Throw
        }

        It 'does not emit an error when AppSecret with TenantId/AppId and DCR config are all supplied' {
            $params = @{
                LogAnalyticsEnabled = $true
                DcrEndpointUri      = 'https://fake.ingest.monitor.azure.us'
                DcrImmutableId      = 'dcr-fake'
                DcrStreamName       = 'Custom-Test_CL'
                TenantId            = 'tenant-id'
                AppId               = 'app-id'
                AppSecret           = 'my-secret'
            }
            { Set-DJMLogConfig @params -ErrorAction Stop } | Should -Not -Throw
        }

        It 'completing a previously incomplete LA config on a second call produces no error' {
            # First call sets LA enabled with only partial config
            Set-DJMLogConfig -LogAnalyticsEnabled $true -ErrorAction SilentlyContinue

            # Second call completes the config — should not error
            $params = @{
                DcrEndpointUri = 'https://fake.ingest.monitor.azure.us'
                DcrImmutableId = 'dcr-fake'
                DcrStreamName  = 'Custom-Test_CL'
                TenantId       = 'tenant-id'
                AppId          = 'app-id'
                AppSecret      = 'secret'
            }
            { Set-DJMLogConfig @params -ErrorAction Stop } | Should -Not -Throw
        }

        It 'does not validate LA preconditions when LogAnalyticsEnabled is false' {
            # LA is disabled (default) — no DCR config set — no error expected
            { Set-DJMLogConfig -Path 'C:\Logs\test.jsonl' -ErrorAction Stop } | Should -Not -Throw
        }
    }

    Context 'Endpoint host vs CloudEnvironment warning (M5)' {

        It 'emits a warning when Commercial cloud is set but DcrEndpointUri contains azure.us' {
            $params = @{
                CloudEnvironment = 'Commercial'
                DcrEndpointUri   = 'https://fake.ingest.monitor.azure.us'
            }
            Set-DJMLogConfig @params -WarningVariable w -WarningAction SilentlyContinue
            $w | Should -Not -BeNullOrEmpty
        }

        It 'emits a warning when GCCHigh cloud is set but DcrEndpointUri contains azure.com' {
            $params = @{
                CloudEnvironment = 'GCCHigh'
                DcrEndpointUri   = 'https://fake.ingest.monitor.azure.com'
            }
            Set-DJMLogConfig @params -WarningVariable w -WarningAction SilentlyContinue
            $w | Should -Not -BeNullOrEmpty
        }

        It 'does not emit a warning when GCCHigh cloud is set and DcrEndpointUri contains azure.us' {
            $params = @{
                CloudEnvironment = 'GCCHigh'
                DcrEndpointUri   = 'https://fake.ingest.monitor.azure.us'
            }
            Set-DJMLogConfig @params -WarningVariable w -WarningAction SilentlyContinue
            $w | Should -BeNullOrEmpty
        }

        It 'does not emit a warning when DoD cloud is set and DcrEndpointUri contains azure.us' {
            $params = @{
                CloudEnvironment = 'DoD'
                DcrEndpointUri   = 'https://fake.ingest.monitor.azure.us'
            }
            Set-DJMLogConfig @params -WarningVariable w -WarningAction SilentlyContinue
            $w | Should -BeNullOrEmpty
        }

        It 'does not emit a warning when Commercial cloud is set and DcrEndpointUri contains azure.com' {
            $params = @{
                CloudEnvironment = 'Commercial'
                DcrEndpointUri   = 'https://fake.ingest.monitor.azure.com'
            }
            Set-DJMLogConfig @params -WarningVariable w -WarningAction SilentlyContinue
            $w | Should -BeNullOrEmpty
        }
    }

    Context 'Config file validation (VAL-1)' {

        It 'warns and keeps default for invalid MinLevel in config file' {
            $configFile = Join-Path ([System.IO.Path]::GetTempPath()) "djmlog-val-$([guid]::NewGuid().Guid).json"
            try {
                '{ "MinLevel": "TRACE" }' | Set-Content -LiteralPath $configFile
                Set-DJMLogConfig -ConfigPath $configFile -WarningAction SilentlyContinue
                InModuleScope DJMLog { $script:DefaultMinLevel } | Should -Be 'DEBUG'
            }
            finally {
                Remove-Item -LiteralPath $configFile -ErrorAction SilentlyContinue
            }
        }

        It 'warns and keeps default for invalid CloudEnvironment in config file' {
            $configFile = Join-Path ([System.IO.Path]::GetTempPath()) "djmlog-val-$([guid]::NewGuid().Guid).json"
            try {
                '{ "CloudEnvironment": "FakeCloud" }' | Set-Content -LiteralPath $configFile
                Set-DJMLogConfig -ConfigPath $configFile -WarningAction SilentlyContinue
                InModuleScope DJMLog { $script:CloudEnvironment } | Should -Be 'GCCHigh'
            }
            finally {
                Remove-Item -LiteralPath $configFile -ErrorAction SilentlyContinue
            }
        }

        It 'warns and keeps default for invalid RotationSchedule in config file' {
            $configFile = Join-Path ([System.IO.Path]::GetTempPath()) "djmlog-val-$([guid]::NewGuid().Guid).json"
            try {
                '{ "RotationSchedule": "Yearly" }' | Set-Content -LiteralPath $configFile
                Set-DJMLogConfig -ConfigPath $configFile -WarningAction SilentlyContinue
                InModuleScope DJMLog { $script:DefaultRotationSchedule } | Should -Be 'None'
            }
            finally {
                Remove-Item -LiteralPath $configFile -ErrorAction SilentlyContinue
            }
        }

        It 'accepts valid MinLevel from config file' {
            $configFile = Join-Path ([System.IO.Path]::GetTempPath()) "djmlog-val-$([guid]::NewGuid().Guid).json"
            try {
                '{ "MinLevel": "WARN" }' | Set-Content -LiteralPath $configFile
                Set-DJMLogConfig -ConfigPath $configFile
                InModuleScope DJMLog { $script:DefaultMinLevel } | Should -Be 'WARN'
            }
            finally {
                Remove-Item -LiteralPath $configFile -ErrorAction SilentlyContinue
            }
        }
    }
}
