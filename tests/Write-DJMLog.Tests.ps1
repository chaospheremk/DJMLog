BeforeAll {
    Import-Module "$PSScriptRoot\..\DJMLog.psd1" -Force
}

Describe 'Write-DJMLog' {

    BeforeEach {
        $script:LogFile = [System.IO.Path]::GetTempFileName()
        Set-DJMLogConfig -Path $script:LogFile
    }

    AfterEach {
        Remove-Item -LiteralPath $script:LogFile -ErrorAction SilentlyContinue
        InModuleScope DJMLog { $script:DefaultLogPath = $null }
    }

    Context 'Basic entry writing' {

        It 'writes a valid JSON line to the log file' {
            Write-DJMLog -Message 'Hello'
            $line = Get-Content -LiteralPath $script:LogFile -Raw
            { $line | ConvertFrom-Json } | Should -Not -Throw
        }

        It 'includes all required fields in the entry' {
            Write-DJMLog -Message 'Required fields'
            $entry = Get-Content -LiteralPath $script:LogFile | ConvertFrom-Json
            $entry.UtcTimestamp  | Should -Not -BeNullOrEmpty
            $entry.Level         | Should -Not -BeNullOrEmpty
            $entry.Message       | Should -Not -BeNullOrEmpty
            $entry.CorrelationId | Should -Not -BeNullOrEmpty
        }

        It 'defaults Level to INFO' {
            Write-DJMLog -Message 'Default level'
            $entry = Get-Content -LiteralPath $script:LogFile | ConvertFrom-Json
            $entry.Level | Should -Be 'INFO'
        }

        It 'uppercases Level regardless of input case' {
            Write-DJMLog -Message 'Case test' -Level 'warn'
            $entry = Get-Content -LiteralPath $script:LogFile | ConvertFrom-Json
            $entry.Level | Should -Be 'WARN'
        }

        It 'records the provided Message' {
            Write-DJMLog -Message 'Specific message text'
            $entry = Get-Content -LiteralPath $script:LogFile | ConvertFrom-Json
            $entry.Message | Should -Be 'Specific message text'
        }

        It 'uses the provided CorrelationId' {
            $cid = (New-Guid).Guid
            Write-DJMLog -Message 'Correlated entry' -CorrelationId $cid
            $entry = Get-Content -LiteralPath $script:LogFile | ConvertFrom-Json
            $entry.CorrelationId | Should -Be $cid
        }

        It 'generates a GUID CorrelationId when none is provided' {
            Write-DJMLog -Message 'Auto GUID'
            $entry = Get-Content -LiteralPath $script:LogFile | ConvertFrom-Json
            { [guid]::Parse($entry.CorrelationId) } | Should -Not -Throw
        }

        It 'appends multiple entries as separate lines' {
            Write-DJMLog -Message 'First'
            Write-DJMLog -Message 'Second'
            Write-DJMLog -Message 'Third'
            $lines = Get-Content -LiteralPath $script:LogFile
            $lines.Count | Should -Be 3
        }

        It 'creates the log directory when it does not exist' {
            $dir     = Join-Path ([System.IO.Path]::GetTempPath()) "djmlog-newdir-$([guid]::NewGuid().Guid)"
            $newLog  = Join-Path $dir 'test.jsonl'
            try {
                Write-DJMLog -Message 'Dir creation' -LogPath $newLog
                Test-Path -LiteralPath $newLog | Should -BeTrue
            }
            finally {
                Remove-Item -LiteralPath $dir -Recurse -ErrorAction SilentlyContinue
            }
        }
    }

    Context '-PassThru' {

        It 'returns the entry as a PSCustomObject when -PassThru is specified' {
            $result = Write-DJMLog -Message 'PassThru test' -PassThru
            $result | Should -BeOfType [PSCustomObject]
        }

        It 'returned object contains the written message' {
            $result = Write-DJMLog -Message 'Verify content' -PassThru
            $result.Message | Should -Be 'Verify content'
        }

        It 'produces no pipeline output when -PassThru is omitted' {
            $result = Write-DJMLog -Message 'Silent write'
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Metadata' {

        It 'writes hashtable metadata under the Metadata key' {
            Write-DJMLog -Message 'Hashtable meta' -Metadata @{ User = 'jsmith'; Count = 5 }
            $entry = Get-Content -LiteralPath $script:LogFile | ConvertFrom-Json
            $entry.Metadata.User  | Should -Be 'jsmith'
            $entry.Metadata.Count | Should -Be 5
        }

        It 'writes PSCustomObject metadata under the Metadata key' {
            $meta = [PSCustomObject]@{ Environment = 'Prod'; Region = 'UKSouth' }
            Write-DJMLog -Message 'PSObject meta' -Metadata $meta
            $entry = Get-Content -LiteralPath $script:LogFile | ConvertFrom-Json
            $entry.Metadata.Environment | Should -Be 'Prod'
            $entry.Metadata.Region      | Should -Be 'UKSouth'
        }

        It 'omits the Metadata key when no metadata is supplied' {
            Write-DJMLog -Message 'No metadata'
            $entry = Get-Content -LiteralPath $script:LogFile | ConvertFrom-Json
            $entry.PSObject.Properties.Name | Should -Not -Contain 'Metadata'
        }
    }

    Context 'Error capture' {

        It 'captures exception message under Metadata.Error.Message when -Level ERROR' {
            try { throw 'Test exception text' } catch {
                Write-DJMLog -Message 'Error entry' -Level ERROR -ErrorObject $_
            }
            $entry = Get-Content -LiteralPath $script:LogFile | ConvertFrom-Json
            $entry.Metadata.Error.Message | Should -Be 'Test exception text'
        }

        It 'captures exception type under Metadata.Error.Type' {
            try { [int]::Parse('not-a-number') } catch {
                Write-DJMLog -Message 'Parse error' -Level ERROR -ErrorObject $_
            }
            $entry = Get-Content -LiteralPath $script:LogFile | ConvertFrom-Json
            $entry.Metadata.Error.Type | Should -Not -BeNullOrEmpty
        }

        It 'emits a warning when -ErrorObject is supplied without -Level ERROR' {
            try { throw 'oops' } catch {
                { Write-DJMLog -Message 'Wrong level' -Level INFO -ErrorObject $_ -WarningAction Stop } |
                    Should -Throw
            }
        }
    }

    Context 'Log rotation' {

        It 'renames the existing log file when MaxSizeMB threshold is exceeded' {
            $dir  = [System.IO.Path]::GetTempPath()
            $base = "djmlog-rot-$([guid]::NewGuid().Guid)"
            $log  = Join-Path $dir "$base.jsonl"
            try {
                # 10 bytes; threshold 0.000009 MB (~9.4 bytes) guarantees rotation
                [System.IO.File]::WriteAllText($log, '1234567890')
                Write-DJMLog -Message 'Rotation trigger' -LogPath $log -MaxSizeMB 0.000009
                $rotated = Get-ChildItem -Path $dir -Filter "${base}_*.jsonl"
                $rotated | Should -Not -BeNullOrEmpty
            }
            finally {
                Get-ChildItem -Path $dir -Filter "${base}*.jsonl" |
                    Remove-Item -ErrorAction SilentlyContinue
            }
        }
    }
}
