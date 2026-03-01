BeforeAll {
    Import-Module "$PSScriptRoot\..\DJMLog.psd1" -Force
}

Describe 'ConvertTo-DJMDictionary' {

    Context 'FromHashtable parameter set' {

        It 'returns a Dictionary[string, PSObject]' {
            $result = ConvertTo-DJMDictionary -Hashtable @{ Foo = 'bar' }
            ($result -is [System.Collections.Generic.Dictionary[string, PSObject]]) | Should -BeTrue
        }

        It 'copies all key-value pairs from the hashtable' {
            $result = ConvertTo-DJMDictionary -Hashtable @{ A = 1; B = 'two'; C = $true }
            $result.Count  | Should -Be 3
            $result['A']   | Should -Be 1
            $result['B']   | Should -Be 'two'
            $result['C']   | Should -Be $true
        }

        It 'preserves hashtable keys without transformation' {
            $result = ConvertTo-DJMDictionary -Hashtable @{ MyKey = 'value' }
            $result.ContainsKey('MyKey') | Should -BeTrue
        }
    }

    Context 'FromObjectList parameter set' {

        It 'indexes each PSObject by the specified key property' {
            $objects = @(
                [PSCustomObject]@{ Name = 'Alice'; Age = 30 }
                [PSCustomObject]@{ Name = 'Bob';   Age = 25 }
            )
            $result = $objects | ConvertTo-DJMDictionary -KeyProperty 'Name'
            $result['alice'].Age | Should -Be 30
            $result['bob'].Age   | Should -Be 25
        }

        It 'lowercases the key value' {
            $obj = [PSCustomObject]@{ Id = 'MyKey'; Value = 42 }
            $result = $obj | ConvertTo-DJMDictionary -KeyProperty 'Id'
            $result.ContainsKey('mykey') | Should -BeTrue
        }

        It 'trims whitespace from the key value' {
            $obj = [PSCustomObject]@{ Id = '  spaced  '; Value = 1 }
            $result = $obj | ConvertTo-DJMDictionary -KeyProperty 'Id'
            $result.ContainsKey('spaced') | Should -BeTrue
        }

        It 'emits a non-terminating error for duplicate keys' {
            $objects = @(
                [PSCustomObject]@{ Name = 'Alice'; Role = 'Admin' }
                [PSCustomObject]@{ Name = 'Alice'; Role = 'User'  }
            )
            { $objects | ConvertTo-DJMDictionary -KeyProperty 'Name' -ErrorAction Stop } |
                Should -Throw
        }

        It 'accepts input via the pipeline' {
            $result = [PSCustomObject]@{ Code = 'X1'; Label = 'Foo' } |
                ConvertTo-DJMDictionary -KeyProperty 'Code'
            $result['x1'].Label | Should -Be 'Foo'
        }

        It 'accepts multiple objects via the pipeline' {
            $result = @(
                [PSCustomObject]@{ Code = 'A'; Val = 1 }
                [PSCustomObject]@{ Code = 'B'; Val = 2 }
                [PSCustomObject]@{ Code = 'C'; Val = 3 }
            ) | ConvertTo-DJMDictionary -KeyProperty 'Code'
            $result.Count | Should -Be 3
        }
    }
}
