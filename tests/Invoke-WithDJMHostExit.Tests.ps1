BeforeAll {
    $script:HelperPath = (Resolve-Path "$PSScriptRoot\..\scripts\Invoke-WithDJMHostExit.ps1").Path
    $script:RepoRoot   = (Resolve-Path "$PSScriptRoot\..").Path
    $script:ModulePath = (Resolve-Path "$PSScriptRoot\..\DJMLog.psd1").Path

    function script:Invoke-HelperSubprocess {
        param (
            [Parameter(Mandatory)] [string]$InnerScript,
            [int]$TimeoutSec = 60
        )
        # Run the helper in a fresh non-interactive pwsh subprocess so its
        # [System.Environment]::Exit does not terminate the test runner.
        $cmd = "& '$script:HelperPath' -Script { $InnerScript }"
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName               = 'pwsh'
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError  = $true
        $startInfo.UseShellExecute        = $false
        $startInfo.CreateNoWindow         = $true
        $startInfo.WorkingDirectory       = $script:RepoRoot
        foreach ($a in @('-NoProfile', '-NonInteractive', '-Command', $cmd)) {
            [void]$startInfo.ArgumentList.Add($a)
        }
        $sw      = [System.Diagnostics.Stopwatch]::StartNew()
        $proc    = [System.Diagnostics.Process]::Start($startInfo)
        $exited  = $proc.WaitForExit($TimeoutSec * 1000)
        $sw.Stop()
        if (-not $exited) {
            try { $proc.Kill($true) } catch { $null = $_ }
            throw "Helper subprocess exceeded ${TimeoutSec}s timeout"
        }
        [pscustomobject]@{
            ExitCode = $proc.ExitCode
            StdOut   = $proc.StandardOutput.ReadToEnd()
            StdErr   = $proc.StandardError.ReadToEnd()
            Elapsed  = $sw.Elapsed
        }
    }
}

Describe 'Invoke-WithDJMHostExit.ps1' {

    Context 'Exit semantics' {

        It 'returns exit code 0 on a successful scriptblock' {
            $result = Invoke-HelperSubprocess -InnerScript "'ok'"
            $result.ExitCode | Should -Be 0
            $result.StdOut.Trim() | Should -Be 'ok'
        }

        It 'returns exit code 1 when the inner scriptblock throws' {
            $result = Invoke-HelperSubprocess -InnerScript "throw 'boom'"
            $result.ExitCode | Should -Be 1
            ($result.StdOut + $result.StdErr) | Should -Match 'boom'
        }

        It 'preserves $LASTEXITCODE from the inner scriptblock' {
            # Use pwsh -Command 'exit 42' as a portable native-exe substitute
            # (cmd.exe is not available on the Linux CI container).
            $result = Invoke-HelperSubprocess -InnerScript "& pwsh -NoProfile -Command 'exit 42'"
            $result.ExitCode | Should -Be 42
        }
    }

    Context 'DJMLog import regression' {

        It 'completes within 30s when the inner block imports DJMLog and writes one entry' {
            # Regression for BUG-023: without [System.Environment]::Exit a
            # `pwsh -Command` subprocess that imports the v2.0 module hangs
            # ~19 min after the script returns.
            $tempLog = Join-Path ([System.IO.Path]::GetTempPath()) ("djmlog-helper-{0}.jsonl" -f ([guid]::NewGuid()))
            try {
                $inner = "Import-Module '$script:ModulePath' -Force; " +
                         "Set-DJMLogConfig -Path '$tempLog'; " +
                         "Write-DJMLog -Message 'helper-smoke' -Level INFO; " +
                         "Wait-DJMLog -TimeoutSec 5 | Out-Null"
                $result = Invoke-HelperSubprocess -InnerScript $inner -TimeoutSec 60
                $result.ExitCode      | Should -Be 0
                $result.Elapsed.TotalSeconds | Should -BeLessThan 30
            }
            finally {
                if (Test-Path $tempLog) { Remove-Item $tempLog -Force -ErrorAction SilentlyContinue }
            }
        }
    }
}
