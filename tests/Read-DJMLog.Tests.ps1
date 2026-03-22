BeforeAll {
    Import-Module "$PSScriptRoot\..\DJMLog.psd1" -Force

    # Write a fixed set of known entries once for the whole file
    $script:LogFile      = [System.IO.Path]::GetTempFileName()
    $script:CorrelationA = (New-Guid).Guid
    $script:CorrelationB = (New-Guid).Guid

    Set-DJMLogConfig -Path $script:LogFile

    Write-DJMLog -Message 'Alpha INFO'    -Level INFO  -CorrelationId $script:CorrelationA
    Write-DJMLog -Message 'Bravo WARN'   -Level WARN  -CorrelationId $script:CorrelationA
    $Params = @{
        Message       = 'Charlie ERROR'
        Level         = 'ERROR'
        CorrelationId = $script:CorrelationB
        Metadata      = @{ Code = 500 }
    }
    Write-DJMLog @Params
    $Params = @{
        Message       = 'Delta DEBUG'
        Level         = 'DEBUG'
        CorrelationId = $script:CorrelationB
        Metadata      = @{ Detail = @{ Sub = 'nested' } }
    }
    Write-DJMLog @Params
}

AfterAll {
    Remove-Item -LiteralPath $script:LogFile -ErrorAction SilentlyContinue
    InModuleScope DJMLog { $script:DefaultLogPath = $null }
}

Describe 'Read-DJMLog' {

    Context 'Basic reading' {

        It 'returns all 4 entries when no filter is applied' {
            $results = Read-DJMLog -LogPath $script:LogFile
            $results.Count | Should -Be 4
        }

        It 'returns PSCustomObjects' {
            $result = Read-DJMLog -LogPath $script:LogFile | Select-Object -First 1
            $result | Should -BeOfType [PSCustomObject]
        }

        It 'every object includes LocalTime, UtcTime, Level, Message, CorrelationId' {
            $results = Read-DJMLog -LogPath $script:LogFile
            foreach ($r in $results) {
                $props = $r.PSObject.Properties.Name
                $props | Should -Contain 'LocalTime'
                $props | Should -Contain 'UtcTime'
                $props | Should -Contain 'Level'
                $props | Should -Contain 'Message'
                $props | Should -Contain 'CorrelationId'
            }
        }

        It 'all returned objects share an identical property set (column normalisation)' {
            $results   = Read-DJMLog -LogPath $script:LogFile
            $propSets  = $results | ForEach-Object { ($_.PSObject.Properties.Name | Sort-Object) -join ',' }
            ($propSets | Select-Object -Unique).Count | Should -Be 1
        }
    }

    Context '-Level filter' {

        It 'returns only entries matching the specified level' {
            $results = Read-DJMLog -LogPath $script:LogFile -Level ERROR
            $results.Count     | Should -Be 1
            $results[0].Level  | Should -Be 'ERROR'
        }

        It 'accepts multiple levels' {
            $results = Read-DJMLog -LogPath $script:LogFile -Level INFO, WARN
            $results.Count | Should -Be 2
        }

        It 'returns an empty result when the level has no matches' {
            $results = Read-DJMLog -LogPath $script:LogFile -Level DEBUG -CorrelationId $script:CorrelationA
            $results.Count | Should -Be 0
        }
    }

    Context '-CorrelationId filter' {

        It 'returns only entries with the matching CorrelationId' {
            $results = Read-DJMLog -LogPath $script:LogFile -CorrelationId $script:CorrelationA
            $results.Count | Should -Be 2
            foreach ($r in $results) {
                $r.CorrelationId | Should -Be $script:CorrelationA
            }
        }
    }

    Context '-MessageContains filter' {

        It 'returns only entries whose Message matches the substring' {
            $results = Read-DJMLog -LogPath $script:LogFile -MessageContains 'Charlie'
            $results.Count       | Should -Be 1
            $results[0].Message  | Should -BeLike '*Charlie*'
        }

        It 'is case-insensitive via wildcard matching' {
            $results = Read-DJMLog -LogPath $script:LogFile -MessageContains 'alpha'
            $results.Count | Should -Be 1
        }
    }

    Context '-Since and -Until filters' {

        It 'returns no entries when -Since is in the future' {
            $results = Read-DJMLog -LogPath $script:LogFile -Since (Get-Date).AddDays(1)
            $results.Count | Should -Be 0
        }

        It 'returns no entries when -Until is in the past' {
            $results = Read-DJMLog -LogPath $script:LogFile -Until (Get-Date).AddDays(-1)
            $results.Count | Should -Be 0
        }

        It 'returns all entries when window contains all timestamps' {
            $Params = @{
                LogPath = $script:LogFile
                Since   = (Get-Date).AddMinutes(-5)
                Until   = (Get-Date).AddMinutes(5)
            }
            $results = Read-DJMLog @Params
            $results.Count | Should -Be 4
        }

        It '-Since boundary is inclusive' {
            $boundaryLog = [System.IO.Path]::GetTempFileName()
            try {
                Write-DJMLog -Message 'Boundary' -LogPath $boundaryLog
                $entryTime = (Read-DJMLog -LogPath $boundaryLog).UtcTime
                (Read-DJMLog -LogPath $boundaryLog -Since $entryTime).Count | Should -Be 1
            }
            finally {
                Remove-Item -LiteralPath $boundaryLog -ErrorAction SilentlyContinue
            }
        }

        It '-Until boundary is inclusive' {
            $boundaryLog = [System.IO.Path]::GetTempFileName()
            try {
                Write-DJMLog -Message 'Boundary' -LogPath $boundaryLog
                $entryTime = (Read-DJMLog -LogPath $boundaryLog).UtcTime
                (Read-DJMLog -LogPath $boundaryLog -Until $entryTime).Count | Should -Be 1
            }
            finally {
                Remove-Item -LiteralPath $boundaryLog -ErrorAction SilentlyContinue
            }
        }
    }

    Context '-First and -Last' {

        It '-First returns the first N entries in file order' {
            $results = Read-DJMLog -LogPath $script:LogFile -First 2
            $results.Count       | Should -Be 2
            $results[0].Message  | Should -Be 'Alpha INFO'
            $results[1].Message  | Should -Be 'Bravo WARN'
        }

        It '-Last returns the last N entries in file order' {
            $results = Read-DJMLog -LogPath $script:LogFile -Last 2
            $results.Count       | Should -Be 2
            $results[0].Message  | Should -Be 'Charlie ERROR'
            $results[1].Message  | Should -Be 'Delta DEBUG'
        }

        It '-First and -Last combined emits a warning and honours -First' {
            { Read-DJMLog -LogPath $script:LogFile -First 1 -Last 1 -WarningAction Stop } |
                Should -Throw
        }

        It '-First returns all entries when N exceeds the total count' {
            $results = Read-DJMLog -LogPath $script:LogFile -First 100
            $results.Count | Should -Be 4
        }

        It '-Last returns all entries when N exceeds the total count' {
            $results = Read-DJMLog -LogPath $script:LogFile -Last 100
            $results.Count | Should -Be 4
        }
    }

    Context 'Metadata flattening' {

        It 'promotes top-level metadata properties to columns' {
            $results = Read-DJMLog -LogPath $script:LogFile -Level ERROR
            $results[0].Code | Should -Be 500
        }

        It 'flattens nested metadata using underscore-separated key paths' {
            $results = Read-DJMLog -LogPath $script:LogFile -Level DEBUG
            $results[0].Detail_Sub | Should -Be 'nested'
        }

        It 'flattens three levels of nested metadata into underscore-separated key paths' {
            $deepLog = [System.IO.Path]::GetTempFileName()
            try {
                Write-DJMLog -Message 'Deep nesting' -LogPath $deepLog -Metadata @{
                    Http = @{ Response = @{ Code = 404 } }
                }
                $results = Read-DJMLog -LogPath $deepLog
                $results[0].Http_Response_Code | Should -Be 404
            }
            finally {
                Remove-Item -LiteralPath $deepLog -ErrorAction SilentlyContinue
            }
        }

        It 'column set reflects only the entries in a sliced result, not all entries in the file' {
            # The full result includes Code (entry 3) and Detail_Sub (entry 4).
            # -First 2 returns only the two entries without metadata; those columns must be absent.
            $results = Read-DJMLog -LogPath $script:LogFile -First 2
            $props   = $results[0].PSObject.Properties.Name
            $props   | Should -Not -Contain 'Code'
            $props   | Should -Not -Contain 'Detail_Sub'
        }
    }

    Context '-Raw' {

        It 'returns strings instead of PSCustomObjects' {
            $result = Read-DJMLog -LogPath $script:LogFile -Raw -First 1
            $result | Should -BeOfType [string]
        }

        It 'returned strings are valid JSON' {
            $result = Read-DJMLog -LogPath $script:LogFile -Raw -First 1
            { ConvertFrom-Json -InputObject $result } | Should -Not -Throw
        }

        It 'filters still apply when -Raw is used' {
            $results = Read-DJMLog -LogPath $script:LogFile -Raw -Level ERROR
            $results.Count | Should -Be 1
            ($results | ConvertFrom-Json).Level | Should -Be 'ERROR'
        }
    }

    Context 'Error handling' {

        It 'emits a warning when the log file does not exist' {
            { Read-DJMLog -LogPath 'C:\DoesNotExist\nope.jsonl' -WarningAction Stop } |
                Should -Throw
        }

        It 'skips invalid JSON lines with a warning and continues' {
            $badLog = [System.IO.Path]::GetTempFileName()
            try {
                # Write one valid entry, one garbage line, one valid entry
                Write-DJMLog -Message 'Before bad line' -LogPath $badLog
                Add-Content -LiteralPath $badLog -Value 'this is not json'
                Write-DJMLog -Message 'After bad line'  -LogPath $badLog

                $results = Read-DJMLog -LogPath $badLog -WarningAction SilentlyContinue
                $results.Count | Should -Be 2
            }
            finally {
                Remove-Item -LiteralPath $badLog -ErrorAction SilentlyContinue
            }
        }

        It 'skips lines with an invalid timestamp with a warning and continues' {
            $badLog = [System.IO.Path]::GetTempFileName()
            try {
                Write-DJMLog -Message 'Before bad timestamp' -LogPath $badLog
                $badLine = '{"UtcTimestamp":"not-a-date","Level":"INFO","Message":"Bad","CorrelationId":"x"}'
                Add-Content -LiteralPath $badLog -Value $badLine
                Write-DJMLog -Message 'After bad timestamp'  -LogPath $badLog

                $results = Read-DJMLog -LogPath $badLog -WarningAction SilentlyContinue
                $results.Count | Should -Be 2
            }
            finally {
                Remove-Item -LiteralPath $badLog -ErrorAction SilentlyContinue
            }
        }

        It 'skips lines missing Level or Message with a warning and continues' {
            $badLog = [System.IO.Path]::GetTempFileName()
            try {
                Write-DJMLog -Message 'Before missing fields' -LogPath $badLog
                $badLine = '{"UtcTimestamp":"2026-01-01T00:00:00.0000000Z","CorrelationId":"x"}'
                Add-Content -LiteralPath $badLog -Value $badLine
                Write-DJMLog -Message 'After missing fields'  -LogPath $badLog

                $results = Read-DJMLog -LogPath $badLog -WarningAction SilentlyContinue
                $results.Count | Should -Be 2
            }
            finally {
                Remove-Item -LiteralPath $badLog -ErrorAction SilentlyContinue
            }
        }
    }

    Context '-Colorize' {

        It 'suppresses pipeline output' {
            $result = Read-DJMLog -LogPath $script:LogFile -Colorize
            $result | Should -BeNullOrEmpty
        }

        It 'returns objects to the pipeline when -PassThru is also specified' {
            $results = Read-DJMLog -LogPath $script:LogFile -Colorize -PassThru
            $results.Count | Should -Be 4
        }
    }

    Context '-ExportCsv' {

        It 'creates a CSV file at the specified path' {
            $csv = Join-Path ([System.IO.Path]::GetTempPath()) "djmlog-test-$([guid]::NewGuid().Guid).csv"
            try {
                Read-DJMLog -LogPath $script:LogFile -ExportCsv -CsvPath $csv
                Test-Path -LiteralPath $csv | Should -BeTrue
            }
            finally {
                Remove-Item -LiteralPath $csv -ErrorAction SilentlyContinue
            }
        }

        It 'suppresses pipeline output' {
            $csv = Join-Path ([System.IO.Path]::GetTempPath()) "djmlog-test-$([guid]::NewGuid().Guid).csv"
            try {
                $result = Read-DJMLog -LogPath $script:LogFile -ExportCsv -CsvPath $csv
                $result | Should -BeNullOrEmpty
            }
            finally {
                Remove-Item -LiteralPath $csv -ErrorAction SilentlyContinue
            }
        }

        It 'returns objects to the pipeline when -PassThru is also specified' {
            $csv = Join-Path ([System.IO.Path]::GetTempPath()) "djmlog-test-$([guid]::NewGuid().Guid).csv"
            try {
                $results = Read-DJMLog -LogPath $script:LogFile -ExportCsv -CsvPath $csv -PassThru
                $results.Count | Should -Be 4
            }
            finally {
                Remove-Item -LiteralPath $csv -ErrorAction SilentlyContinue
            }
        }
    }
}
