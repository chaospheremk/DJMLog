BeforeAll {
    Import-Module "$PSScriptRoot\..\DJMLog.psd1" -Force
}

Describe 'ConvertTo-DJMOrderedPSObject' {

    It 'returns a PSCustomObject' {
        $result = ConvertTo-DJMOrderedPSObject -Dictionary ([ordered]@{ A = 1 })
        $result | Should -BeOfType [PSCustomObject]
    }

    It 'copies all key-value pairs' {
        $result = ConvertTo-DJMOrderedPSObject -Dictionary ([ordered]@{ Name = 'Test'; Count = 99 })
        $result.Name  | Should -Be 'Test'
        $result.Count | Should -Be 99
    }

    It 'preserves key enumeration order' {
        $result = ConvertTo-DJMOrderedPSObject -Dictionary ([ordered]@{ Z = 1; A = 2; M = 3 })
        $props = $result.PSObject.Properties.Name
        $props[0] | Should -Be 'Z'
        $props[1] | Should -Be 'A'
        $props[2] | Should -Be 'M'
    }

    It 'accepts a generic Dictionary[string, PSObject] produced by ConvertTo-DJMDictionary' {
        $dict   = ConvertTo-DJMDictionary -Hashtable @{ Env = 'Prod'; Region = 'UKSouth' }
        $result = ConvertTo-DJMOrderedPSObject -Dictionary $dict
        $result.Env    | Should -Be 'Prod'
        $result.Region | Should -Be 'UKSouth'
    }

    It 'accepts a plain Hashtable' {
        $result = ConvertTo-DJMOrderedPSObject -Dictionary @{ Foo = 'bar' }
        $result.Foo | Should -Be 'bar'
    }

    It 'handles a single-entry dictionary' {
        $result = ConvertTo-DJMOrderedPSObject -Dictionary ([ordered]@{ Only = 'one' })
        ($result.PSObject.Properties | Measure-Object).Count | Should -Be 1
        $result.Only | Should -Be 'one'
    }
}
