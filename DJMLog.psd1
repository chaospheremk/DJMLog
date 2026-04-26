@{
    RootModule        = 'DJMLog.psm1'
    ModuleVersion     = '2.0.0'
    GUID              = 'a7b3c5d1-e2f4-4a6b-8c9d-0e1f2a3b4c5d'
    Author            = 'Doug Johnson'
    Description       = 'Async structured JSONL logging module for PowerShell 7+ with multi-sink fan-out, schema v2, redaction, sampling, and Azure Log Analytics ingestion.'
    PowerShellVersion = '7.0'

    FunctionsToExport = @(
        'Set-DJMLogConfig'
        'Write-DJMLog'
        'Read-DJMLog'
        'Send-DJMLogBuffer'
        'Flush-DJMLog'
        'Wait-DJMLog'
        'Start-DJMActivity'
        'Stop-DJMActivity'
        'Get-DJMLogDiagnostics'
        'ConvertTo-DJMDictionary'
        'ConvertTo-DJMOrderedPSObject'
    )

    CmdletsToExport   = @()
    AliasesToExport   = @()
    VariablesToExport = @()
}
