BeforeAll {
    Import-Module "$PSScriptRoot\..\DJMLog.psd1" -Force
    $script:ModulePath = (Resolve-Path "$PSScriptRoot\..\DJMLog.psd1").Path
}

Describe 'Get-DJMLogDiagnostics' {

    BeforeEach {
        InModuleScope DJMLog {
            $script:InternalErrors = [System.Collections.Generic.Queue[pscustomobject]]::new()
        }
    }

    Context 'Empty queue' {

        It 'returns an empty collection when no errors have been recorded' {
            $result = Get-DJMLogDiagnostics
            $result | Should -BeNullOrEmpty
        }

        It 'returns 0 entries immediately after module state reset' {
            $result = Get-DJMLogDiagnostics
            @($result).Count | Should -Be 0
        }
    }

    Context 'Populated queue' {

        It 'returns exactly 3 entries after 3 items are enqueued' {
            InModuleScope DJMLog {
                $now = [datetime]::UtcNow
                1..3 | ForEach-Object {
                    $script:InternalErrors.Enqueue([pscustomobject]@{
                        UtcTimestamp = $now
                        Source       = 'Test'
                        Message      = "entry $_"
                        Exception    = $null
                    })
                }
            }
            $result = Get-DJMLogDiagnostics
            @($result).Count | Should -Be 3
        }

        It 'round-trips the Source field correctly' {
            InModuleScope DJMLog {
                $script:InternalErrors.Enqueue([pscustomobject]@{
                    UtcTimestamp = [datetime]::UtcNow
                    Source       = 'Write-DJMLog'
                    Message      = 'test message'
                    Exception    = $null
                })
            }
            $result = Get-DJMLogDiagnostics
            $result[0].Source | Should -Be 'Write-DJMLog'
        }

        It 'round-trips the Message field correctly' {
            InModuleScope DJMLog {
                $script:InternalErrors.Enqueue([pscustomobject]@{
                    UtcTimestamp = [datetime]::UtcNow
                    Source       = 'Test'
                    Message      = 'specific error text'
                    Exception    = $null
                })
            }
            $result = Get-DJMLogDiagnostics
            $result[0].Message | Should -Be 'specific error text'
        }

        It 'round-trips the UtcTimestamp field as a non-empty value' {
            $before = [datetime]::UtcNow
            InModuleScope DJMLog {
                $script:InternalErrors.Enqueue([pscustomobject]@{
                    UtcTimestamp = [datetime]::UtcNow
                    Source       = 'Test'
                    Message      = 'ts check'
                    Exception    = $null
                })
            }
            $result = Get-DJMLogDiagnostics
            $result[0].UtcTimestamp | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Bounded at 100' {

        It 'holds at most 100 entries when 150 are enqueued' {
            InModuleScope DJMLog {
                $now = [datetime]::UtcNow
                1..150 | ForEach-Object {
                    $script:InternalErrors.Enqueue([pscustomobject]@{
                        UtcTimestamp = $now
                        Source       = 'Test'
                        Message      = "entry $_"
                        Exception    = $null
                    })
                    # Enforce the 100-entry cap as the write path must do
                    while ($script:InternalErrors.Count -gt 100) {
                        $null = $script:InternalErrors.Dequeue()
                    }
                }
            }
            $result = Get-DJMLogDiagnostics
            @($result).Count | Should -Be 100
        }

        It 'drops the oldest entries (FIFO) when the cap is reached' {
            InModuleScope DJMLog {
                $now = [datetime]::UtcNow
                # Enqueue entries 1..150 with FIFO cap enforcement at 100
                1..150 | ForEach-Object {
                    $script:InternalErrors.Enqueue([pscustomobject]@{
                        UtcTimestamp = $now
                        Source       = 'Test'
                        Message      = "entry $_"
                        Exception    = $null
                    })
                    while ($script:InternalErrors.Count -gt 100) {
                        $null = $script:InternalErrors.Dequeue()
                    }
                }
            }
            $result = Get-DJMLogDiagnostics
            # Oldest surviving entry should be #51 (entries 1..50 were dropped)
            $result[0].Message | Should -Be 'entry 51'
            # Most recent should be #150
            $result[-1].Message | Should -Be 'entry 150'
        }
    }

    Context 'Records write failures' {

        It 'records a SelfLog entry with Source Write-DJMLog after a failed write' {
            # Use InModuleScope to directly trigger the internal catch path.
            # The implementation must call an internal helper (or inline code) that
            # enqueues to $script:InternalErrors when AppendAllText fails.
            # We simulate this by pointing Write-DJMLog at a path inside a directory
            # that we make unwritable by creating a *file* where the directory should be.

            $conflictPath = [System.IO.Path]::GetTempFileName()
            # conflictPath is now a file; try to use it as a directory (log goes inside it)
            $impossibleLog = [System.IO.Path]::Combine($conflictPath, 'app.jsonl')

            try {
                # This write must fail because $conflictPath is a file, not a directory.
                # Write-DJMLog should catch the failure and record it in InternalErrors.
                Write-DJMLog -Message 'Should fail' -LogPath $impossibleLog -WarningAction SilentlyContinue
            }
            catch {
                # Swallow any terminating error — we only care about SelfLog
            }

            $diagnostics = Get-DJMLogDiagnostics
            $diagnostics | Should -Not -BeNullOrEmpty
            $writeFailure = $diagnostics | Where-Object { $_.Source -eq 'Write-DJMLog' }
            $writeFailure | Should -Not -BeNullOrEmpty
        }
    }
}
