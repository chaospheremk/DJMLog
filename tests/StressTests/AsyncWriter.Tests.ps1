BeforeAll {
    # Stress test exercises the async path explicitly — disable any global
    # sync-writes flag the surrounding test runner may have set.
    $env:DJMLOG_SYNC_WRITES = $null
    Import-Module "$PSScriptRoot\..\..\DJMLog.psd1" -Force
    $script:ModulePath = (Resolve-Path "$PSScriptRoot\..\..\DJMLog.psd1").Path
}

AfterAll {
    Remove-Module DJMLog -Force -ErrorAction SilentlyContinue
}

Describe 'AsyncWriter stress' -Tag 'Stress' {

    BeforeEach {
        $script:LogFile = [System.IO.Path]::GetTempFileName()
        Remove-Item -LiteralPath $script:LogFile -ErrorAction SilentlyContinue
    }

    AfterEach {
        Remove-Item -LiteralPath $script:LogFile -ErrorAction SilentlyContinue
    }

    It '16 runspaces x 5000 entries -> 80000 lines, no JSON corruption' {
        $cid = (New-Guid).Guid
        $threads = 16
        $perThread = 5000
        $logFile  = $script:LogFile
        $modulePath = $script:ModulePath

        # Each parallel runspace imports DJMLog (gets its own writer runspace +
        # channel). All writers append to the same file; the named OS mutex
        # serialises file appends across runspaces. Each runspace explicitly
        # Flushes before returning so its own writer drains before disposal.
        $results = 1..$threads | ForEach-Object -Parallel {
            $tid = $_
            $modPath  = $using:modulePath
            $log      = $using:logFile
            $count    = $using:perThread
            $traceId  = $using:cid

            Import-Module $modPath -Force
            Set-DJMLogConfig -Path $log -ChannelCapacity 100000
            for ($i = 0; $i -lt $count; $i++) {
                Write-DJMLog -Message "t${tid}-${i}" -CorrelationId $traceId -NoCaller -NoHostContext 6>$null
            }
            $drained = Flush-DJMLog -TimeoutSec 30
            return [pscustomobject]@{ ThreadId = $tid; Drained = $drained }
        } -ThrottleLimit $threads

        $results.Count                                       | Should -Be $threads
        ($results | Where-Object Drained -eq $false).Count   | Should -Be 0

        $lineCount = (Get-Content -LiteralPath $script:LogFile).Count
        $lineCount | Should -Be ($threads * $perThread)

        # Sample 50 random lines and confirm each parses as JSON with a matching CorrelationId
        $lines  = Get-Content -LiteralPath $script:LogFile
        $sample = $lines | Get-Random -Count 50
        foreach ($line in $sample) {
            $obj = $line | ConvertFrom-Json -Depth 12
            $obj.CorrelationId | Should -Be $cid
        }
    }
}
