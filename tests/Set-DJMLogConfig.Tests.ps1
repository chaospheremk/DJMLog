BeforeAll {
    Import-Module "$PSScriptRoot\..\DJMLog.psd1" -Force
}

Describe 'Set-DJMLogConfig' {

    BeforeEach {
        # Reset module state to known defaults before every test
        InModuleScope DJMLog {
            $script:DefaultLogPath        = $null
            $script:DefaultMaxSizeMB      = 0
            $script:DefaultMutexTimeoutMs = 2000
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

        It 'explicit -Path overrides config file Path' {
            '{ "Path": "C:\\Logs\\from-file.jsonl" }' | Set-Content -LiteralPath $script:ConfigFile
            Set-DJMLogConfig -ConfigPath $script:ConfigFile -Path 'C:\Logs\override.jsonl'
            InModuleScope DJMLog { $script:DefaultLogPath } | Should -Be 'C:\Logs\override.jsonl'
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
}
