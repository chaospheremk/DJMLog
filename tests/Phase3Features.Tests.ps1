BeforeAll {
    Import-Module "$PSScriptRoot\..\DJMLog.psd1" -Force
}

AfterAll {
    Remove-Module DJMLog -Force -ErrorAction SilentlyContinue
}

Describe 'Phase 3 — Schema v2 + enrichment' {
    BeforeEach {
        $script:LogFile = [System.IO.Path]::GetTempFileName()
        Set-DJMLogConfig -Path $script:LogFile
    }
    AfterEach {
        Remove-Item -LiteralPath $script:LogFile -ErrorAction SilentlyContinue
    }

    It 'emits SchemaVersion = "2"' {
        Write-DJMLog -Message 'schema check' -NoCaller
        $entry = Get-Content $script:LogFile | Select-Object -First 1 | ConvertFrom-Json
        $entry.SchemaVersion | Should -Be '2'
    }

    It 'emits SeverityNumber matching the OTel mapping' {
        Write-DJMLog -Message 'i' -Level INFO  -NoCaller
        Write-DJMLog -Message 'w' -Level WARN  -NoCaller
        Write-DJMLog -Message 'e' -Level ERROR -NoCaller
        Write-DJMLog -Message 'd' -Level DEBUG -NoCaller
        Write-DJMLog -Message 'f' -Level FATAL -NoCaller
        $entries = Get-Content $script:LogFile | ForEach-Object { $_ | ConvertFrom-Json }
        ($entries | Where-Object Level -eq 'INFO').SeverityNumber  | Should -Be 9
        ($entries | Where-Object Level -eq 'WARN').SeverityNumber  | Should -Be 13
        ($entries | Where-Object Level -eq 'ERROR').SeverityNumber | Should -Be 17
        ($entries | Where-Object Level -eq 'DEBUG').SeverityNumber | Should -Be 5
        ($entries | Where-Object Level -eq 'FATAL').SeverityNumber | Should -Be 21
    }

    It 'includes Host enrichment by default' {
        Write-DJMLog -Message 'host check' -NoCaller
        $entry = Get-Content $script:LogFile | Select-Object -First 1 | ConvertFrom-Json
        $entry.Host                | Should -Not -BeNullOrEmpty
        $entry.Host.MachineName    | Should -Be ([System.Environment]::MachineName)
        $entry.Host.UserName       | Should -Be ([System.Environment]::UserName)
        $entry.Host.PSVersion      | Should -Not -BeNullOrEmpty
    }

    It '-NoHostContext suppresses Host enrichment for that call' {
        Write-DJMLog -Message 'host suppress' -NoCaller -NoHostContext
        $entry = Get-Content $script:LogFile | Select-Object -First 1 | ConvertFrom-Json
        $entry.PSObject.Properties['Host'] | Should -BeNullOrEmpty
    }

    It 'accepts FATAL level' {
        Write-DJMLog -Message 'fatal' -Level FATAL -NoCaller
        $entry = Get-Content $script:LogFile | Select-Object -First 1 | ConvertFrom-Json
        $entry.Level          | Should -Be 'FATAL'
        $entry.SeverityNumber | Should -Be 21
    }
}

Describe 'Phase 3 — Read-DJMLog v1 / v2 schema auto-detect' {
    BeforeEach {
        $script:LogFile = [System.IO.Path]::GetTempFileName()
    }
    AfterEach {
        Remove-Item -LiteralPath $script:LogFile -ErrorAction SilentlyContinue
    }

    It 'treats entries without SchemaVersion as v1 and backfills SeverityNumber' {
        $v1 = '{"UtcTimestamp":"2026-04-26T00:00:00.000Z","Level":"INFO","Message":"v1 entry","CorrelationId":"00000000-0000-0000-0000-000000000001"}'
        Set-Content -LiteralPath $script:LogFile -Value $v1 -Encoding utf8
        $row = Read-DJMLog -LogPath $script:LogFile | Select-Object -First 1
        $row.SchemaVersion  | Should -Be '1'
        $row.SeverityNumber | Should -Be 9    # backfilled from INFO
    }

    It 'preserves SchemaVersion = "2" when present' {
        $v2 = '{"SchemaVersion":"2","UtcTimestamp":"2026-04-26T00:00:00.000Z","Level":"INFO","SeverityNumber":9,"Message":"v2 entry","CorrelationId":"00000000-0000-0000-0000-000000000002"}'
        Set-Content -LiteralPath $script:LogFile -Value $v2 -Encoding utf8
        $row = Read-DJMLog -LogPath $script:LogFile | Select-Object -First 1
        $row.SchemaVersion  | Should -Be '2'
        $row.SeverityNumber | Should -Be 9
    }
}

Describe 'Phase 3 — Read-DJMLog -Stream' {
    BeforeEach {
        $script:LogFile = [System.IO.Path]::GetTempFileName()
        Set-DJMLogConfig -Path $script:LogFile
    }
    AfterEach {
        Remove-Item -LiteralPath $script:LogFile -ErrorAction SilentlyContinue
    }

    It 'emits entries to the pipeline as they are parsed' {
        1..5 | ForEach-Object { Write-DJMLog -Message "stream-$_" -NoCaller -NoHostContext }
        $rows = Read-DJMLog -LogPath $script:LogFile -Stream
        $rows.Count | Should -Be 5
    }

    It '-Stream is incompatible with -First and emits a warning' {
        Write-DJMLog -Message 'one' -NoCaller -NoHostContext
        $w = $null
        $rows = Read-DJMLog -LogPath $script:LogFile -Stream -First 1 -WarningVariable w -WarningAction SilentlyContinue
        $w | Should -Not -BeNullOrEmpty
        $rows.Count | Should -Be 1
    }
}

Describe 'Phase 3 — Activities' {
    BeforeEach {
        $script:LogFile = [System.IO.Path]::GetTempFileName()
        Set-DJMLogConfig -Path $script:LogFile
        InModuleScope DJMLog { $script:ActivityStack = $null }
    }
    AfterEach {
        Remove-Item -LiteralPath $script:LogFile -ErrorAction SilentlyContinue
        InModuleScope DJMLog { $script:ActivityStack = $null }
    }

    It 'Start-DJMActivity returns a frame with Id, Name, StartUtc, CorrelationId' {
        $frame = Start-DJMActivity -Name 'Test'
        $frame.Name          | Should -Be 'Test'
        $frame.Id            | Should -Not -BeNullOrEmpty
        $frame.StartUtc      | Should -Not -BeNullOrEmpty
        $frame.CorrelationId | Should -Not -BeNullOrEmpty
        $frame.ParentId      | Should -BeNullOrEmpty
        Stop-DJMActivity | Out-Null
    }

    It 'sets ParentId on the second nested activity' {
        $a = Start-DJMActivity -Name 'Outer'
        $b = Start-DJMActivity -Name 'Inner'
        $b.ParentId | Should -Be $a.Id
        Stop-DJMActivity | Out-Null
        Stop-DJMActivity | Out-Null
    }

    It 'Write-DJMLog inherits CorrelationId from the active activity' {
        $cid = (New-Guid).Guid
        Start-DJMActivity -Name 'Test' -CorrelationId $cid | Out-Null
        Write-DJMLog -Message 'in activity' -NoCaller -NoHostContext
        Stop-DJMActivity | Out-Null
        $entry = Get-Content $script:LogFile | Select-Object -First 1 | ConvertFrom-Json
        $entry.CorrelationId | Should -Be $cid
    }

    It 'Stop-DJMActivity emits a duration entry and pops the stack' {
        Start-DJMActivity -Name 'WithDuration' | Out-Null
        Start-Sleep -Milliseconds 30
        Stop-DJMActivity | Out-Null
        InModuleScope DJMLog { $script:ActivityStack.Count } | Should -Be 0
        # The Stop-DJMActivity Write-DJMLog call landed on the file
        Get-Content $script:LogFile | Should -Match 'WithDuration'
    }

    It 'Stop-DJMActivity warns when stack is empty' {
        $w = $null
        Stop-DJMActivity -WarningVariable w -WarningAction SilentlyContinue | Out-Null
        $w | Should -Not -BeNullOrEmpty
    }
}

Describe 'Phase 3 — Redaction' {
    BeforeEach {
        $script:LogFile = [System.IO.Path]::GetTempFileName()
        Set-DJMLogConfig -Path $script:LogFile -RedactionPatterns @() -RedactionPresets @()
    }
    AfterEach {
        Remove-Item -LiteralPath $script:LogFile -ErrorAction SilentlyContinue
    }

    It 'redacts SecureString metadata values to [REDACTED]' {
        $secret = ConvertTo-SecureString -String 'super-secret' -AsPlainText -Force
        Write-DJMLog -Message 'with secure string' -Metadata @{ Token = $secret } -NoCaller -NoHostContext
        $entry = Get-Content $script:LogFile | Select-Object -First 1 | ConvertFrom-Json
        $entry.Metadata.Token | Should -Be '[REDACTED]'
    }

    It 'redacts metadata values whose key matches password/secret/token/apikey' {
        Write-DJMLog -Message 'sensitive keys' -Metadata @{ Password = 'p@ss'; ApiKey = 'k123' } -NoCaller -NoHostContext
        $entry = Get-Content $script:LogFile | Select-Object -First 1 | ConvertFrom-Json
        $entry.Metadata.Password | Should -Be '[REDACTED]'
        $entry.Metadata.ApiKey   | Should -Be '[REDACTED]'
    }

    It 'applies BearerToken preset to redact bearer tokens in strings' {
        Set-DJMLogConfig -RedactionPresets @('BearerToken')
        Write-DJMLog -Message 'header is Bearer abc123XYZ' -NoCaller -NoHostContext
        $entry = Get-Content $script:LogFile | Select-Object -First 1 | ConvertFrom-Json
        $entry.Message | Should -Match '\[REDACTED\]'
    }

    It 'applies a configured regex to redact matching strings' {
        Set-DJMLogConfig -RedactionPatterns @('SECRET-\d+')
        Write-DJMLog -Message 'leak: SECRET-42' -NoCaller -NoHostContext
        $entry = Get-Content $script:LogFile | Select-Object -First 1 | ConvertFrom-Json
        $entry.Message | Should -Match '\[REDACTED\]'
    }
}

Describe 'Phase 3 — Sampling' {
    BeforeEach {
        $script:LogFile = [System.IO.Path]::GetTempFileName()
        Set-DJMLogConfig -Path $script:LogFile -SampleRate @{}
    }
    AfterEach {
        Remove-Item -LiteralPath $script:LogFile -ErrorAction SilentlyContinue
    }

    It 'drops all entries when SampleRate is 0.0 for that level' {
        Set-DJMLogConfig -SampleRate @{ INFO = 0.0 }
        1..50 | ForEach-Object { Write-DJMLog -Message "drop-$_" -Level INFO -NoCaller -NoHostContext }
        # Some entries may be processed before the sample drop kicks in for non-async path,
        # but with SampleRate = 0.0 the drop happens synchronously before the channel write.
        # The file should be empty.
        if (Test-Path $script:LogFile) {
            $count = (Get-Content $script:LogFile -ErrorAction SilentlyContinue | Measure-Object).Count
            $count | Should -Be 0
        }
    }

    It 'keeps all entries when SampleRate is 1.0' {
        Set-DJMLogConfig -SampleRate @{ INFO = 1.0 }
        1..20 | ForEach-Object { Write-DJMLog -Message "keep-$_" -Level INFO -NoCaller -NoHostContext }
        (Get-Content $script:LogFile).Count | Should -Be 20
    }
}

Describe 'Phase 3 — Flush-DJMLog / Wait-DJMLog' {
    It 'Flush-DJMLog returns $true when the channel drains' {
        $tmp = [System.IO.Path]::GetTempFileName()
        Set-DJMLogConfig -Path $tmp
        try {
            1..10 | ForEach-Object { Write-DJMLog -Message "fl-$_" -NoCaller -NoHostContext }
            $ok = Flush-DJMLog -TimeoutSec 5
            $ok | Should -Be $true
        }
        finally { Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue }
    }

    It 'Wait-DJMLog with positive timeout returns $true on a drained channel' {
        $tmp = [System.IO.Path]::GetTempFileName()
        Set-DJMLogConfig -Path $tmp
        try {
            Write-DJMLog -Message 'wait' -NoCaller -NoHostContext
            $ok = Wait-DJMLog -TimeoutSec 5
            $ok | Should -Be $true
        }
        finally { Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue }
    }
}

Describe 'Phase 3 — Get-DJMLogDiagnostics channel stats' {
    It 'reports EnqueuedCount / ProcessedCount / DroppedCount / QueuedCount' {
        $tmp = [System.IO.Path]::GetTempFileName()
        Set-DJMLogConfig -Path $tmp
        try {
            Write-DJMLog -Message 'stats-1' -NoCaller -NoHostContext
            Write-DJMLog -Message 'stats-2' -NoCaller -NoHostContext
            [void](Flush-DJMLog -TimeoutSec 5)
            $diag = Get-DJMLogDiagnostics
            $diag.PSObject.Properties['EnqueuedCount']  | Should -Not -BeNullOrEmpty
            $diag.PSObject.Properties['ProcessedCount'] | Should -Not -BeNullOrEmpty
            $diag.PSObject.Properties['DroppedCount']   | Should -Not -BeNullOrEmpty
            $diag.PSObject.Properties['QueuedCount']    | Should -Not -BeNullOrEmpty
            $diag.EnqueuedCount  | Should -BeGreaterThan 0
            $diag.ProcessedCount | Should -BeGreaterThan 0
            $diag.DroppedCount   | Should -Be 0
        }
        finally { Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue }
    }
}

Describe 'Phase 3 — Sinks configuration' {
    It 'accepts -Sinks with multiple values via Set-DJMLogConfig' {
        Set-DJMLogConfig -Sinks @('File', 'Console')
        InModuleScope DJMLog {
            $script:Sinks | Should -Be @('File', 'Console')
        }
    }
    It 'accepts -ChannelCapacity via Set-DJMLogConfig' {
        Set-DJMLogConfig -ChannelCapacity 5000
        InModuleScope DJMLog {
            $script:ChannelCapacity | Should -Be 5000
        }
    }
}
