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
}
