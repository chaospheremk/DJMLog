---
document type: module
Help Version: 1.0.0.0
HelpInfoUri: ''
Locale: en-US
Module Guid: a7b3c5d1-e2f4-4a6b-8c9d-0e1f2a3b4c5d
Module Name: DJMLog
ms.date: 03/08/2026
PlatyPS schema version: 2024-05-01
title: DJMLog Module
---

# DJMLog Module

## Description

Structured JSONL logging module for PowerShell 7+ automation scripts.

## DJMLog Cmdlets

### [ConvertTo-DJMDictionary](ConvertTo-DJMDictionary.md)

Converts PSObjects or a hashtable into a Dictionary[string, PSObject].

### [ConvertTo-DJMOrderedPSObject](ConvertTo-DJMOrderedPSObject.md)

Converts an IDictionary into a PSCustomObject with stable property order.

### [Read-DJMLog](Read-DJMLog.md)

Reads and filters a JSONL log file produced by Write-DJMLog.

### [Send-DJMLogBuffer](Send-DJMLogBuffer.md)

Flushes the in-memory log buffer to Azure Log Analytics via the Logs Ingestion API.

### [Set-DJMLogConfig](Set-DJMLogConfig.md)

Configures module-level defaults for Write-DJMLog, Read-DJMLog, and Send-DJMLogBuffer.

### [Write-DJMLog](Write-DJMLog.md)

Appends a structured entry to a JSONL log file.

