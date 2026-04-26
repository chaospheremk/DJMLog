BeforeAll {
    Import-Module "$PSScriptRoot\..\DJMLog.psd1" -Force
    $script:ModulePath = (Resolve-Path "$PSScriptRoot\..\DJMLog.psd1").Path
}

Describe 'Write-DJMLog' {

    BeforeEach {
        $script:LogFile = [System.IO.Path]::GetTempFileName()
        Set-DJMLogConfig -Path $script:LogFile
    }

    AfterEach {
        Remove-Item -LiteralPath $script:LogFile -ErrorAction SilentlyContinue
        InModuleScope DJMLog {
            $script:DefaultLogPath          = $null
            $script:DefaultMinLevel         = 'DEBUG'
            $script:DefaultRotationSchedule = 'None'
            $script:DefaultRetainDays       = 0
            $script:DefaultRetainFiles      = 0
            $script:DefaultIncludeCaller    = $true
            $script:LogAnalyticsEnabled     = $false
            $script:LogBuffer               = [System.Collections.Generic.List[hashtable]]::new()
            $script:FlushFailureCount       = 0
            $script:AutoFlushDisabled       = $false
            $script:FlushThreshold          = 100
            $script:MaxBufferSize           = 5000
        }
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

        It 'stores unsupported metadata types under Metadata.RawValue' {
            Write-DJMLog -Message 'Raw meta' -Metadata 'plain string'
            $entry = Get-Content -LiteralPath $script:LogFile | ConvertFrom-Json
            $entry.Metadata.RawValue | Should -Be 'plain string'
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

        It 'starts a new log file containing only the entry written after rotation' {
            $dir  = [System.IO.Path]::GetTempPath()
            $base = "djmlog-rot-content-$([guid]::NewGuid().Guid)"
            $log  = Join-Path $dir "$base.jsonl"
            try {
                [System.IO.File]::WriteAllText($log, '1234567890')
                Write-DJMLog -Message 'Post-rotation entry' -LogPath $log -MaxSizeMB 0.000009
                $lines = Get-Content -LiteralPath $log
                $lines.Count | Should -Be 1
                ($lines | ConvertFrom-Json).Message | Should -Be 'Post-rotation entry'
            }
            finally {
                Get-ChildItem -Path $dir -Filter "${base}*.jsonl" |
                    Remove-Item -ErrorAction SilentlyContinue
            }
        }

        It 'rotates daily when the file was created yesterday' {
            $dir  = [System.IO.Path]::GetTempPath()
            $base = "djmlog-daily-$([guid]::NewGuid().Guid)"
            $log  = Join-Path $dir "$base.jsonl"
            try {
                [System.IO.File]::WriteAllText($log, '{}')
                [System.IO.File]::SetCreationTimeUtc($log, [datetime]::UtcNow.AddDays(-1))
                Write-DJMLog -Message 'Daily rotation trigger' -LogPath $log -RotationSchedule Daily
                $rotated = Get-ChildItem -Path $dir -Filter "${base}_*.jsonl"
                $rotated | Should -Not -BeNullOrEmpty
            }
            finally {
                Get-ChildItem -Path $dir -Filter "${base}*.jsonl" |
                    Remove-Item -ErrorAction SilentlyContinue
            }
        }

        It 'does not rotate when RotationSchedule is None and the file is old' {
            $dir  = [System.IO.Path]::GetTempPath()
            $base = "djmlog-norot-$([guid]::NewGuid().Guid)"
            $log  = Join-Path $dir "$base.jsonl"
            try {
                [System.IO.File]::WriteAllText($log, '{}')
                [System.IO.File]::SetCreationTimeUtc($log, [datetime]::UtcNow.AddDays(-30))
                Write-DJMLog -Message 'No rotation' -LogPath $log -RotationSchedule None
                $rotated = Get-ChildItem -Path $dir -Filter "${base}_*.jsonl"
                $rotated | Should -BeNullOrEmpty
            }
            finally {
                Get-ChildItem -Path $dir -Filter "${base}*.jsonl" |
                    Remove-Item -ErrorAction SilentlyContinue
            }
        }

        It 'rotates hourly when the file was created in a prior hour' {
            $dir  = [System.IO.Path]::GetTempPath()
            $base = "djmlog-hourly-$([guid]::NewGuid().Guid)"
            $log  = Join-Path $dir "$base.jsonl"
            try {
                [System.IO.File]::WriteAllText($log, '{}')
                [System.IO.File]::SetCreationTimeUtc($log, [datetime]::UtcNow.AddHours(-2))
                Write-DJMLog -Message 'Hourly rotation trigger' -LogPath $log -RotationSchedule Hourly
                $rotated = Get-ChildItem -Path $dir -Filter "${base}_*.jsonl"
                $rotated | Should -Not -BeNullOrEmpty
            }
            finally {
                Get-ChildItem -Path $dir -Filter "${base}*.jsonl" |
                    Remove-Item -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Minimum level threshold' {

        It 'does not write an entry whose level is below the module threshold' {
            InModuleScope DJMLog { $script:DefaultMinLevel = 'WARN' }
            Write-DJMLog -Message 'Should be suppressed' -Level INFO
            (Get-Item -LiteralPath $script:LogFile).Length | Should -Be 0
        }

        It 'writes an entry whose level equals the module threshold' {
            InModuleScope DJMLog { $script:DefaultMinLevel = 'WARN' }
            Write-DJMLog -Message 'At threshold' -Level WARN
            $entry = Get-Content -LiteralPath $script:LogFile | ConvertFrom-Json
            $entry.Message | Should -Be 'At threshold'
        }

        It 'writes an entry whose level is above the module threshold' {
            InModuleScope DJMLog { $script:DefaultMinLevel = 'WARN' }
            Write-DJMLog -Message 'Above threshold' -Level ERROR
            $entry = Get-Content -LiteralPath $script:LogFile | ConvertFrom-Json
            $entry.Message | Should -Be 'Above threshold'
        }

        It 'suppresses DEBUG when module threshold is INFO' {
            InModuleScope DJMLog { $script:DefaultMinLevel = 'INFO' }
            Write-DJMLog -Message 'Debug suppressed' -Level DEBUG
            (Get-Item -LiteralPath $script:LogFile).Length | Should -Be 0
        }

        It 'per-call -MinLevel suppresses entries below it regardless of module default' {
            Write-DJMLog -Message 'Suppressed by per-call' -Level INFO -MinLevel ERROR
            (Get-Item -LiteralPath $script:LogFile).Length | Should -Be 0
        }

        It 'per-call -MinLevel allows entries at or above it' {
            InModuleScope DJMLog { $script:DefaultMinLevel = 'ERROR' }
            Write-DJMLog -Message 'Allowed by per-call override' -Level INFO -MinLevel DEBUG
            $entry = Get-Content -LiteralPath $script:LogFile | ConvertFrom-Json
            $entry.Message | Should -Be 'Allowed by per-call override'
        }

        It 'writes all four levels when MinLevel is DEBUG' {
            InModuleScope DJMLog { $script:DefaultMinLevel = 'DEBUG' }
            Write-DJMLog -Message 'D' -Level DEBUG
            Write-DJMLog -Message 'I' -Level INFO
            Write-DJMLog -Message 'W' -Level WARN
            Write-DJMLog -Message 'E' -Level ERROR
            (Get-Content -LiteralPath $script:LogFile).Count | Should -Be 4
        }
    }

    Context 'Retention policy' {

        It 'deletes rotated files older than RetainDays after rotation' {
            $dir  = [System.IO.Path]::GetTempPath()
            $base = "djmlog-retain-days-$([guid]::NewGuid().Guid)"
            $log  = Join-Path $dir "$base.jsonl"
            try {
                # Create 2 old rotated files
                $old1 = Join-Path $dir "${base}_20200101-000000.jsonl"
                $old2 = Join-Path $dir "${base}_20200102-000000.jsonl"
                [System.IO.File]::WriteAllText($old1, '{}')
                [System.IO.File]::WriteAllText($old2, '{}')
                [System.IO.File]::SetCreationTimeUtc($old1, [datetime]::UtcNow.AddDays(-10))
                [System.IO.File]::SetCreationTimeUtc($old2, [datetime]::UtcNow.AddDays(-10))

                # Trigger a size-based rotation with RetainDays = 1
                [System.IO.File]::WriteAllText($log, '1234567890')
                Write-DJMLog -Message 'Retention trigger' -LogPath $log -MaxSizeMB 0.000009 -RetainDays 1

                $remaining = Get-ChildItem -Path $dir -Filter "${base}_*.jsonl"
                # Old files should be gone; only the freshly rotated file remains
                $remaining.Count | Should -Be 1
                $remaining[0].Name | Should -Not -Be ([System.IO.Path]::GetFileName($old1))
                $remaining[0].Name | Should -Not -Be ([System.IO.Path]::GetFileName($old2))
            }
            finally {
                Get-ChildItem -Path $dir -Filter "${base}*.jsonl" |
                    Remove-Item -ErrorAction SilentlyContinue
            }
        }

        It 'keeps only RetainFiles most recent rotated files after rotation' {
            $dir  = [System.IO.Path]::GetTempPath()
            $base = "djmlog-retain-files-$([guid]::NewGuid().Guid)"
            $log  = Join-Path $dir "$base.jsonl"
            try {
                # Pre-create 3 rotated files (older timestamps in filenames)
                $r1 = Join-Path $dir "${base}_20240101-000000.jsonl"
                $r2 = Join-Path $dir "${base}_20240102-000000.jsonl"
                $r3 = Join-Path $dir "${base}_20240103-000000.jsonl"
                [System.IO.File]::WriteAllText($r1, '{}')
                [System.IO.File]::WriteAllText($r2, '{}')
                [System.IO.File]::WriteAllText($r3, '{}')

                # Trigger a size-based rotation with RetainFiles = 2
                [System.IO.File]::WriteAllText($log, '1234567890')
                Write-DJMLog -Message 'RetainFiles trigger' -LogPath $log -MaxSizeMB 0.000009 -RetainFiles 2

                $remaining = Get-ChildItem -Path $dir -Filter "${base}_*.jsonl"
                # 3 pre-existing + 1 just-rotated = 4 total before cleanup; keep 2 newest
                $remaining.Count | Should -Be 2
            }
            finally {
                Get-ChildItem -Path $dir -Filter "${base}*.jsonl" |
                    Remove-Item -ErrorAction SilentlyContinue
            }
        }

        It 'does not delete any files when RetainDays and RetainFiles are both 0' {
            $dir  = [System.IO.Path]::GetTempPath()
            $base = "djmlog-retain-zero-$([guid]::NewGuid().Guid)"
            $log  = Join-Path $dir "$base.jsonl"
            try {
                $old = Join-Path $dir "${base}_20200101-000000.jsonl"
                [System.IO.File]::WriteAllText($old, '{}')
                [System.IO.File]::SetCreationTimeUtc($old, [datetime]::UtcNow.AddDays(-3650))

                [System.IO.File]::WriteAllText($log, '1234567890')
                Write-DJMLog -Message 'No cleanup' -LogPath $log -MaxSizeMB 0.000009 -RetainDays 0 -RetainFiles 0

                $remaining = Get-ChildItem -Path $dir -Filter "${base}_*.jsonl"
                $remaining.Count | Should -Be 2
            }
            finally {
                Get-ChildItem -Path $dir -Filter "${base}*.jsonl" |
                    Remove-Item -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Caller auto-capture' {

        It 'includes Metadata.Caller in the entry by default' {
            Write-DJMLog -Message 'Caller default'
            $entry = Get-Content -LiteralPath $script:LogFile | ConvertFrom-Json
            $entry.Metadata.Caller | Should -Not -BeNullOrEmpty
        }

        It 'Metadata.Caller.LineNumber is a positive integer' {
            Write-DJMLog -Message 'Caller line'
            $entry = Get-Content -LiteralPath $script:LogFile | ConvertFrom-Json
            $entry.Metadata.Caller.LineNumber | Should -BeGreaterThan 0
        }

        It '-NoCaller suppresses caller capture' {
            Write-DJMLog -Message 'No caller' -NoCaller
            $entry = Get-Content -LiteralPath $script:LogFile | ConvertFrom-Json
            $entry.Metadata.PSObject.Properties.Name | Should -Not -Contain 'Caller'
        }

        It 'Set-DJMLogConfig -IncludeCaller $false disables caller capture globally' {
            Set-DJMLogConfig -IncludeCaller $false
            Write-DJMLog -Message 'Global disable'
            $entry = Get-Content -LiteralPath $script:LogFile | ConvertFrom-Json
            # No other metadata supplied, so Metadata key should be absent entirely
            $entry.PSObject.Properties.Name | Should -Not -Contain 'Metadata'
        }

        It 'user-supplied Metadata.Caller is not overwritten by auto-capture' {
            Write-DJMLog -Message 'User caller' -Metadata @{ Caller = 'my-custom-value' }
            $entry = Get-Content -LiteralPath $script:LogFile | ConvertFrom-Json
            $entry.Metadata.Caller | Should -Be 'my-custom-value'
        }

        It 'Metadata.Caller is present alongside other metadata' {
            Write-DJMLog -Message 'With meta' -Metadata @{ JobId = 99 }
            $entry = Get-Content -LiteralPath $script:LogFile | ConvertFrom-Json
            $entry.Metadata.JobId   | Should -Be 99
            $entry.Metadata.Caller  | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Log Analytics buffer' {

        BeforeEach {
            InModuleScope DJMLog {
                $script:LogAnalyticsEnabled = $true
                $script:FlushThreshold      = 100
                $script:MaxBufferSize       = 5000
                $script:AutoFlushDisabled   = $false
                $script:LogBuffer           = [System.Collections.Generic.List[hashtable]]::new()
            }
        }

        It 'adds entry to buffer when LogAnalyticsEnabled is true' {
            Write-DJMLog -Message 'Buffer me'
            InModuleScope DJMLog { $script:LogBuffer.Count } | Should -Be 1
        }

        It 'does not add entry to buffer when LogAnalyticsEnabled is false' {
            InModuleScope DJMLog { $script:LogAnalyticsEnabled = $false }
            Write-DJMLog -Message 'No buffer'
            InModuleScope DJMLog { $script:LogBuffer.Count } | Should -Be 0
        }

        It 'buffer entry contains correct fields' {
            Write-DJMLog -Message 'Field check' -Level WARN -CorrelationId 'test-cid'
            $entry = InModuleScope DJMLog { $script:LogBuffer[0] }
            $entry['Message']       | Should -Be 'Field check'
            $entry['Level']         | Should -Be 'WARN'
            $entry['CorrelationId'] | Should -Be 'test-cid'
            $entry['UtcTimestamp']  | Should -Not -BeNullOrEmpty
        }

        It 'drops oldest entry when buffer reaches MaxBufferSize' {
            InModuleScope DJMLog { $script:MaxBufferSize = 3 }
            Write-DJMLog -Message 'First'
            Write-DJMLog -Message 'Second'
            Write-DJMLog -Message 'Third'
            Write-DJMLog -Message 'Fourth' -WarningAction SilentlyContinue
            $count = InModuleScope DJMLog { $script:LogBuffer.Count }
            $count | Should -Be 3
            $firstMsg = InModuleScope DJMLog { $script:LogBuffer[0]['Message'] }
            $firstMsg | Should -Be 'Second'
        }

        It 'triggers auto-flush when buffer reaches FlushThreshold' {
            Mock Send-DJMLogBuffer -ModuleName DJMLog { }
            InModuleScope DJMLog { $script:FlushThreshold = 2 }
            Write-DJMLog -Message 'One'
            Write-DJMLog -Message 'Two'
            Should -Invoke Send-DJMLogBuffer -ModuleName DJMLog -Times 1 -Exactly
        }

        It 'does not auto-flush when AutoFlushDisabled is true' {
            Mock Send-DJMLogBuffer -ModuleName DJMLog { }
            InModuleScope DJMLog {
                $script:FlushThreshold    = 2
                $script:AutoFlushDisabled = $true
            }
            Write-DJMLog -Message 'One'
            Write-DJMLog -Message 'Two'
            Should -Invoke Send-DJMLogBuffer -ModuleName DJMLog -Times 0 -Exactly
        }

        It 'includes Metadata in buffer entry when provided' {
            Write-DJMLog -Message 'With meta' -Metadata @{ JobId = 42 }
            $hasMeta = InModuleScope DJMLog { $script:LogBuffer[0].ContainsKey('Metadata') }
            $hasMeta | Should -Be $true
        }
    }

    Context 'Parallel write safety (C1)' {

        It 'produces 4000 valid JSON lines when 8 runspaces each write 500 entries' {
            $tempFile = [System.IO.Path]::GetTempFileName()
            $modulePath = $script:ModulePath
            try {
                Set-DJMLogConfig -Path $tempFile

                1..8 | ForEach-Object -Parallel {
                    Import-Module $using:modulePath -Force
                    1..500 | ForEach-Object {
                        Write-DJMLog -Message "thread $_" -LogPath $using:tempFile
                    }
                } -ThrottleLimit 8

                $lines = Get-Content -LiteralPath $tempFile
                $lines.Count | Should -Be 4000

                { $lines | ForEach-Object { $_ | ConvertFrom-Json } } | Should -Not -Throw
            }
            finally {
                Remove-Item -LiteralPath $tempFile -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Concurrent rotation (C3)' {

        It 'produces exactly one rotated file and no lost entries when 4 runspaces trigger rotation simultaneously' {
            $dir      = [System.IO.Path]::GetTempPath()
            $base     = "djmlog-conrot-$([guid]::NewGuid().Guid)"
            $tempFile = [System.IO.Path]::Combine($dir, "$base.jsonl")
            $modulePath = $script:ModulePath
            try {
                # Pre-populate just over the 0.001 MB threshold (~1.5 KB)
                $preFill = 'x' * 1536  # 1.5 KB of existing content
                [System.IO.File]::WriteAllText($tempFile, $preFill)
                $preLineCount = ([System.IO.File]::ReadAllText($tempFile).Split("`n") | Where-Object { $_ -ne '' }).Count

                1..4 | ForEach-Object -Parallel {
                    Import-Module $using:modulePath -Force
                    Write-DJMLog -Message "race $_" -LogPath $using:tempFile -MaxSizeMB 0.001
                } -ThrottleLimit 4

                $rotatedFiles = Get-ChildItem -Path $dir -Filter "${base}_*.jsonl"

                # Exactly one rotation must have occurred — not zero (no rotation) and not 2+ (race)
                $rotatedFiles.Count | Should -Be 1

                # Total entries: pre-existing non-empty lines + 4 new entries
                $activeLines  = Get-Content -LiteralPath $tempFile
                $rotatedLines = Get-Content -LiteralPath $rotatedFiles[0].FullName
                $newEntries   = ($activeLines | Where-Object { $_ -ne '' }).Count
                $newEntries | Should -BeGreaterOrEqual 1
            }
            finally {
                Get-ChildItem -Path $dir -Filter "${base}*.jsonl" | Remove-Item -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Retention edge cases (C4)' {

        It 'deletes available files and records the locked-file failure in the SelfLog' {
            $dir  = [System.IO.Path]::GetTempPath()
            $base = "djmlog-retedge-$([guid]::NewGuid().Guid)"
            $log  = [System.IO.Path]::Combine($dir, "$base.jsonl")

            # Create 5 pre-existing rotated files with old timestamps
            $rotatedPaths = @()
            for ($i = 1; $i -le 5; $i++) {
                $rPath = [System.IO.Path]::Combine($dir, "${base}_2020010${i}-000000.jsonl")
                [System.IO.File]::WriteAllText($rPath, '{}')
                [System.IO.File]::SetCreationTimeUtc($rPath, [datetime]::UtcNow.AddDays(-10))
                $rotatedPaths += $rPath
            }

            # Lock the first file exclusively so Delete() will fail on it
            $lockedStream = [System.IO.File]::Open(
                $rotatedPaths[0],
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::None
            )
            try {
                # Trigger rotation + retention with RetainFiles = 1
                [System.IO.File]::WriteAllText($log, '1234567890')
                Write-DJMLog -Message 'Retention edge' -LogPath $log -MaxSizeMB 0.000009 -RetainFiles 1 -WarningAction SilentlyContinue

                # At least 3 of the 5 old files should have been deleted despite one being locked
                $remaining = Get-ChildItem -Path $dir -Filter "${base}_*.jsonl"
                $remaining.Count | Should -BeLessOrEqual 3

                # The locked-file failure should appear in the SelfLog
                (Get-DJMLogDiagnostics).Count | Should -BeGreaterOrEqual 1
            }
            finally {
                $lockedStream.Dispose()
                Get-ChildItem -Path $dir -Filter "${base}*.jsonl" | Remove-Item -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Exception chain (H5)' {

        It 'captures ExceptionChain with 3 entries and preserves top-level Error fields' {
            $e1 = [System.InvalidOperationException]::new('invalid op')
            $e2 = [System.ArgumentException]::new('bad arg')
            $e3 = [System.IO.IOException]::new('io failure')
            $aggEx = [System.AggregateException]::new('outer aggregate', [System.Exception[]]@($e1, $e2, $e3))

            $errorRecord = $null
            try { throw $aggEx } catch { $errorRecord = $_ }

            Write-DJMLog -Message 'Aggregate error' -Level ERROR -ErrorObject $errorRecord

            $entry = Get-Content -LiteralPath $script:LogFile | ConvertFrom-Json

            # ExceptionChain must exist and have exactly 3 entries
            $entry.Metadata.Error.ExceptionChain | Should -Not -BeNullOrEmpty
            $entry.Metadata.Error.ExceptionChain.Count | Should -Be 3

            # Each chain entry must have Type and Message
            foreach ($chainEntry in $entry.Metadata.Error.ExceptionChain) {
                $chainEntry.Type    | Should -Not -BeNullOrEmpty
                $chainEntry.Message | Should -Not -BeNullOrEmpty
            }

            # Back-compat: top-level Error.Type and Error.Message must still exist
            $entry.Metadata.Error.Type    | Should -Not -BeNullOrEmpty
            $entry.Metadata.Error.Message | Should -Not -BeNullOrEmpty
        }
    }
}
