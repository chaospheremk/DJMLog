@{
    RootModule        = 'DJMLog.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'a7b3c5d1-e2f4-4a6b-8c9d-0e1f2a3b4c5d'
    Author            = 'Doug Johnson'
    Description       = 'Structured JSONL logging module for PowerShell 7+ automation scripts.'
    PowerShellVersion = '7.0'

    FunctionsToExport = @(
        'Set-DJMLogConfig'
        'Write-DJMLog'
        'Read-DJMLog'
        'Send-DJMLogBuffer'
        'ConvertTo-DJMDictionary'
        'ConvertTo-DJMOrderedPSObject'
    )

    CmdletsToExport   = @()
    AliasesToExport   = @()
    VariablesToExport = @()
}
