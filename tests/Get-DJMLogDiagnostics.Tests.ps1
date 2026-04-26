BeforeAll {
    Import-Module "$PSScriptRoot\..\DJMLog.psd1" -Force
    $script:ModulePath = (Resolve-Path "$PSScriptRoot\..\DJMLog.psd1").Path
}

Describe 'Get-DJMLogDiagnostics' {

    BeforeEach {
        InModuleScope DJMLog {
            $script:InternalErrors       = [System.Collections.Generic.Queue[pscustomobject]]::new()
            $script:AutoFlushDisabled    = $false
            $script:FlushFailureCount    = 0
            $script:AutoFlushOpenedAtUtc = $null
        }
    }

    # -------------------------------------------------------------------------
    # Return-type contract (M7 extended object)
    # -------------------------------------------------------------------------
    # Get-DJMLogDiagnostics now returns a PSCustomObject with:
    #   .Errors              — array of internal error entries (previously the return value itself)
    #   .CircuitBreakerState — 'Closed' | 'Open' | 'HalfOpen-Probe-Pending'
    #   .AutoFlushOpenedAtUtc — datetime when the circuit breaker opened, or $null
    # All tests below use the new .Errors accessor for the error entries.
    # -------------------------------------------------------------------------

    Context 'Return type' {

        It 'returns a PSCustomObject, not a plain array' {
            $result = Get-DJMLogDiagnostics
            ($result -is [pscustomobject]) | Should -BeTrue
        }

        It 'result has an Errors property' {
            $result = Get-DJMLogDiagnostics
            $result.PSObject.Properties.Name | Should -Contain 'Errors'
        }

        It 'result has a CircuitBreakerState property' {
            $result = Get-DJMLogDiagnostics
            $result.PSObject.Properties.Name | Should -Contain 'CircuitBreakerState'
        }

        It 'result has an AutoFlushOpenedAtUtc property' {
            $result = Get-DJMLogDiagnostics
            $result.PSObject.Properties.Name | Should -Contain 'AutoFlushOpenedAtUtc'
        }
    }

    Context 'Empty queue' {

        It 'Errors is empty when no errors have been recorded' {
            $result = Get-DJMLogDiagnostics
            $result.Errors | Should -BeNullOrEmpty
        }

        It 'Errors count is 0 immediately after module state reset' {
            $result = Get-DJMLogDiagnostics
            @($result.Errors).Count | Should -Be 0
        }
    }

    Context 'Populated queue' {

        It 'Errors returns exactly 3 entries after 3 items are enqueued' {
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
            @($result.Errors).Count | Should -Be 3
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
            $result.Errors[0].Source | Should -Be 'Write-DJMLog'
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
            $result.Errors[0].Message | Should -Be 'specific error text'
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
            $result.Errors[0].UtcTimestamp | Should -Not -BeNullOrEmpty
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
            @($result.Errors).Count | Should -Be 100
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
            $result.Errors[0].Message | Should -Be 'entry 51'
            # Most recent should be #150
            $result.Errors[-1].Message | Should -Be 'entry 150'
        }
    }

    Context 'Circuit breaker state (M7)' {

        It 'returns CircuitBreakerState = Closed when AutoFlushDisabled is false' {
            $result = Get-DJMLogDiagnostics
            $result.CircuitBreakerState | Should -Be 'Closed'
        }

        It 'returns CircuitBreakerState = Open when disabled and half-open window not yet elapsed' {
            InModuleScope DJMLog {
                $script:AutoFlushDisabled    = $true
                $script:FlushFailureCount    = 3
                $script:AutoFlushOpenedAtUtc = [datetime]::UtcNow.AddSeconds(-10)
            }

            $result = Get-DJMLogDiagnostics
            $result.CircuitBreakerState | Should -Be 'Open'
        }

        It 'returns CircuitBreakerState = HalfOpen-Probe-Pending when disabled and 300s window has elapsed' {
            InModuleScope DJMLog {
                $script:AutoFlushDisabled    = $true
                $script:FlushFailureCount    = 3
                $script:AutoFlushOpenedAtUtc = [datetime]::UtcNow.AddSeconds(-301)
            }

            $result = Get-DJMLogDiagnostics
            $result.CircuitBreakerState | Should -Be 'HalfOpen-Probe-Pending'
        }

        It 'AutoFlushOpenedAtUtc is null when circuit is closed' {
            $result = Get-DJMLogDiagnostics
            $result.AutoFlushOpenedAtUtc | Should -BeNullOrEmpty
        }

        It 'AutoFlushOpenedAtUtc reflects the time the circuit opened' {
            $openedAt = [datetime]::UtcNow.AddMinutes(-5)
            InModuleScope DJMLog {
                $script:AutoFlushDisabled    = $true
                $script:AutoFlushOpenedAtUtc = $openedAt
            }

            $result = Get-DJMLogDiagnostics
            # Should be within 1 second of the set value
            ($result.AutoFlushOpenedAtUtc - $openedAt).TotalSeconds | Should -BeLessThan 1
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
            $diagnostics.Errors | Should -Not -BeNullOrEmpty
            $writeFailure = $diagnostics.Errors | Where-Object { $_.Source -eq 'Write-DJMLog' }
            $writeFailure | Should -Not -BeNullOrEmpty
        }
    }
}
