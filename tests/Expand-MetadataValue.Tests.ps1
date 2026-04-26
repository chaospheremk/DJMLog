BeforeAll {
    Import-Module "$PSScriptRoot\..\DJMLog.psd1" -Force
}

Describe 'Expand-MetadataValue' {

    BeforeEach {
        $script:Target = [System.Collections.Generic.Dictionary[string, PSObject]]::new()
    }

    Context 'Flat values' {

        It 'stores a string value at the given prefix' {
            InModuleScope DJMLog {
                $target = [System.Collections.Generic.Dictionary[string, PSObject]]::new()
                Expand-MetadataValue -Prefix 'Key' -Value 'hello' -Target $target
                $target['Key'] | Should -Be 'hello'
            }
        }

        It 'stores an integer value at the given prefix' {
            InModuleScope DJMLog {
                $target = [System.Collections.Generic.Dictionary[string, PSObject]]::new()
                Expand-MetadataValue -Prefix 'Count' -Value 42 -Target $target
                $target['Count'] | Should -Be 42
            }
        }

        It 'stores $null value at the given prefix' {
            InModuleScope DJMLog {
                $target = [System.Collections.Generic.Dictionary[string, PSObject]]::new()
                Expand-MetadataValue -Prefix 'Empty' -Value $null -Target $target
                $target.ContainsKey('Empty') | Should -BeTrue
                $target['Empty'] | Should -BeNullOrEmpty
            }
        }
    }

    Context 'Nested PSCustomObject' {

        It 'flattens a one-level nested object with underscore-joined keys' {
            InModuleScope DJMLog {
                $target = [System.Collections.Generic.Dictionary[string, PSObject]]::new()
                $value = [PSCustomObject]@{ Name = 'test'; Code = 200 }
                Expand-MetadataValue -Prefix 'Http' -Value $value -Target $target
                $target['Http_Name'] | Should -Be 'test'
                $target['Http_Code'] | Should -Be 200
            }
        }

        It 'flattens a two-level nested object' {
            InModuleScope DJMLog {
                $target = [System.Collections.Generic.Dictionary[string, PSObject]]::new()
                $value = [PSCustomObject]@{
                    Response = [PSCustomObject]@{ Code = 404; Text = 'Not Found' }
                }
                Expand-MetadataValue -Prefix 'Http' -Value $value -Target $target
                $target['Http_Response_Code'] | Should -Be 404
                $target['Http_Response_Text'] | Should -Be 'Not Found'
            }
        }

        It 'flattens a three-level nested object' {
            InModuleScope DJMLog {
                $target = [System.Collections.Generic.Dictionary[string, PSObject]]::new()
                $value = [PSCustomObject]@{
                    A = [PSCustomObject]@{
                        B = [PSCustomObject]@{ C = 'deep' }
                    }
                }
                Expand-MetadataValue -Prefix 'Root' -Value $value -Target $target
                $target['Root_A_B_C'] | Should -Be 'deep'
            }
        }
    }

    Context 'Empty PSCustomObject' {

        It 'stores an empty PSCustomObject as a leaf value' {
            InModuleScope DJMLog {
                $target = [System.Collections.Generic.Dictionary[string, PSObject]]::new()
                $value = [PSCustomObject]@{}
                Expand-MetadataValue -Prefix 'Empty' -Value $value -Target $target
                $target.ContainsKey('Empty') | Should -BeTrue
            }
        }
    }

    Context 'MaxDepth limit' {

        It 'stops recursing at MaxDepth and stores the remaining object as-is' {
            InModuleScope DJMLog {
                $target = [System.Collections.Generic.Dictionary[string, PSObject]]::new()
                $value = [PSCustomObject]@{
                    A = [PSCustomObject]@{
                        B = [PSCustomObject]@{ C = 'deep' }
                    }
                }
                Expand-MetadataValue -Prefix 'Root' -Value $value -Target $target -MaxDepth 1
                # Depth 1 expands Root -> Root_A, but Root_A's value (PSCustomObject with B)
                # hits depth 0 and is stored as-is
                $target.ContainsKey('Root_A') | Should -BeTrue
                $target['Root_A'] | Should -BeOfType [PSCustomObject]
            }
        }

        It 'stores value immediately when MaxDepth is 0' {
            InModuleScope DJMLog {
                $target = [System.Collections.Generic.Dictionary[string, PSObject]]::new()
                $value = [PSCustomObject]@{ A = 1 }
                Expand-MetadataValue -Prefix 'Root' -Value $value -Target $target -MaxDepth 0
                $target.ContainsKey('Root') | Should -BeTrue
                $target['Root'] | Should -BeOfType [PSCustomObject]
            }
        }

        It 'fully expands when depth is sufficient (default 10)' {
            InModuleScope DJMLog {
                $target = [System.Collections.Generic.Dictionary[string, PSObject]]::new()
                $value = [PSCustomObject]@{ X = 'leaf' }
                Expand-MetadataValue -Prefix 'P' -Value $value -Target $target
                $target['P_X'] | Should -Be 'leaf'
            }
        }
    }

    Context 'Cycle detection (C2)' {

        It 'terminates and stores a cycle marker for a self-referencing object' {
            InModuleScope DJMLog {
                $target = [System.Collections.Generic.Dictionary[string, PSObject]]::new()
                $o = [PSCustomObject]@{ Name = 'a' }
                $o | Add-Member -MemberType NoteProperty -Name Self -Value $o

                # Must not hang or stack-overflow — the test runner timeout proves termination
                Expand-MetadataValue -Prefix 'Root' -Value $o -Target $target

                # Sibling property must still be expanded normally
                $target['Root_Name'] | Should -Be 'a'

                # The cycle must be marked rather than recursed into
                $target['Root_Self'] | Should -Be '<cycle>'
            }
        }

        It 'terminates and expands siblings while marking the cycle for mutual recursion' {
            InModuleScope DJMLog {
                $target = [System.Collections.Generic.Dictionary[string, PSObject]]::new()
                $a = [PSCustomObject]@{ Label = 'nodeA' }
                $b = [PSCustomObject]@{ Label = 'nodeB' }
                $a | Add-Member -MemberType NoteProperty -Name Other -Value $b
                $b | Add-Member -MemberType NoteProperty -Name Other -Value $a

                # Must not hang or stack-overflow
                Expand-MetadataValue -Prefix 'Root' -Value $a -Target $target

                # Sibling Label properties must both expand correctly. This proves the
                # visited-set Remove() in finally restored state for siblings rather
                # than leaving them poisoned as already-visited.
                $target['Root_Label']        | Should -Be 'nodeA'
                $target['Root_Other_Label']  | Should -Be 'nodeB'

                # The cycle (a -> b -> a) must be marked rather than recursed into.
                $target['Root_Other_Other'] | Should -Be '<cycle>'
            }
        }
    }
}
