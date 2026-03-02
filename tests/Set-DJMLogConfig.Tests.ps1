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
}
