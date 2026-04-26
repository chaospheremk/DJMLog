# Command Reference

| Command | Description |
|---------|-------------|
| [ConvertTo-DJMDictionary](ConvertTo-DJMDictionary.md) | Converts PSObjects or a hashtable into a Dictionary[string, PSObject] |
| [ConvertTo-DJMOrderedPSObject](ConvertTo-DJMOrderedPSObject.md) | Converts an IDictionary into a PSCustomObject with stable property order |
| [Get-DJMLogDiagnostics](Get-DJMLogDiagnostics.md) | Returns the module's internal error queue (SelfLog) plus circuit breaker state |
| [Read-DJMLog](Read-DJMLog.md) | Reads and filters a JSONL log file produced by Write-DJMLog |
| [Send-DJMLogBuffer](Send-DJMLogBuffer.md) | Flushes the in-memory log buffer to Azure Log Analytics via the Logs Ingestion API |
| [Set-DJMLogConfig](Set-DJMLogConfig.md) | Configures module-level defaults for Write-DJMLog, Read-DJMLog, and Send-DJMLogBuffer |
| [Write-DJMLog](Write-DJMLog.md) | Appends a structured entry to a JSONL log file |

