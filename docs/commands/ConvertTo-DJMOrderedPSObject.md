---
document type: cmdlet
external help file: DJMLog-Help.xml
HelpUri: ''
Locale: en-US
Module Name: DJMLog
ms.date: 03/08/2026
PlatyPS schema version: 2024-05-01
title: ConvertTo-DJMOrderedPSObject
---

# ConvertTo-DJMOrderedPSObject

## SYNOPSIS

Converts an IDictionary into a PSCustomObject with stable property order.

## SYNTAX

### __AllParameterSets

```
ConvertTo-DJMOrderedPSObject [-Dictionary] <IDictionary> [<CommonParameters>]
```

## ALIASES

None.

## DESCRIPTION

Iterates the source dictionary's keys in enumeration order, copies each
key-value pair into an [ordered] hashtable, and casts the result to
PSCustomObject.
The property order of the returned object matches the
key enumeration order of the input dictionary.

Accepts any type implementing IDictionary, including Hashtable,
OrderedDictionary, and Dictionary[string, PSObject].

## EXAMPLES

### EXAMPLE 1

```powershell
# Convert a generic dictionary returned by ConvertTo-DJMDictionary
$dict   = ConvertTo-DJMDictionary -Hashtable @{ Name = 'Prod'; Region = 'UKSouth' }
$object = ConvertTo-DJMOrderedPSObject -Dictionary $dict
$object | Format-List
```

## PARAMETERS

### -Dictionary

The source dictionary to convert.

```yaml
Type: System.Collections.IDictionary
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

None. This cmdlet does not accept pipeline input.

## OUTPUTS

### System.Management.Automation.PSObject

A PSCustomObject with properties in the same order as the source dictionary keys.

## NOTES

## RELATED LINKS

