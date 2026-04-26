# Command Reference

| Command | Description |
|---------|-------------|
| [ConvertTo-DJMDictionary](ConvertTo-DJMDictionary.md) | Converts PSObjects or a hashtable into a Dictionary[string, PSObject] |
| [ConvertTo-DJMOrderedPSObject](ConvertTo-DJMOrderedPSObject.md) | Converts an IDictionary into a PSCustomObject with stable property order |
| [Flush-DJMLog](Flush-DJMLog.md) | Drains the async writer channel and (if Log Analytics is enabled) flushes the in-memory buffer |
| [Get-DJMLogDiagnostics](Get-DJMLogDiagnostics.md) | Returns the module's internal error queue (SelfLog) plus circuit breaker state |
| [Read-DJMLog](Read-DJMLog.md) | Reads and filters a JSONL log file produced by Write-DJMLog |
| [Send-DJMLogBuffer](Send-DJMLogBuffer.md) | Back-compat wrapper. Forwards to Flush-DJMLog (v2.0 async writer ADR-019) |
| [Set-DJMLogConfig](Set-DJMLogConfig.md) | Configures module-level defaults for Write-DJMLog, Read-DJMLog, and Send-DJMLogBuffer |
| [Start-DJMActivity](Start-DJMActivity.md) | Pushes a new activity scope onto the per-runspace activity stack |
| [Stop-DJMActivity](Stop-DJMActivity.md) | Pops the most recently pushed activity scope and emits a duration entry |
| [Wait-DJMLog](Wait-DJMLog.md) | Blocks until the async writer channel has drained, with a timeout |
| [Write-DJMLog](Write-DJMLog.md) | Submits a structured entry to the async writer for fan-out across the configured sinks |

