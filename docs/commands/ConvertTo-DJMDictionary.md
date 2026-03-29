---
document type: cmdlet
external help file: DJMLog-Help.xml
HelpUri: ''
Locale: en-US
Module Name: DJMLog
ms.date: 03/28/2026
PlatyPS schema version: 2024-05-01
title: ConvertTo-DJMDictionary
---

# ConvertTo-DJMDictionary

## SYNOPSIS

Converts PSObjects or a hashtable into a Dictionary[string, PSObject].

## SYNTAX

### FromObjectList

```
ConvertTo-DJMDictionary -InputObject <psobject> -KeyProperty <string> [<CommonParameters>]
```

### FromHashtable

```
ConvertTo-DJMDictionary -Hashtable <hashtable> [<CommonParameters>]
```

## ALIASES

None.
## DESCRIPTION

Accepts input via two mutually exclusive parameter sets:

  FromObjectList
      Each PSObject (piped or passed directly) is added to the dictionary
      using the value of the specified property as its key.
Keys are
      trimmed and lowercased before insertion.
Duplicate keys emit a
      non-terminating error and the second object is discarded.

  FromHashtable
      Each key-value pair in the hashtable is copied into the dictionary
      as-is, with no key transformation applied.

## EXAMPLES

### EXAMPLE 1

# Build a lookup from an AD query
$userIndex = Get-ADUser -Filter * -Properties Department |
    ConvertTo-DJMDictionary -KeyProperty 'SamAccountName'
$userIndex['jsmith'].Department

### EXAMPLE 2

# Convert a hashtable of config values
$config = ConvertTo-DJMDictionary -Hashtable @{
    Environment = 'Production'
    Region      = 'UKSouth'
}

## PARAMETERS

### -Hashtable

A hashtable to convert.
Keys are copied without transformation.

```yaml
Type: System.Collections.Hashtable
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: FromHashtable
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -InputObject

One or more PSObjects to index.
Accepts pipeline input.
Each object must
have a property matching the name supplied to -KeyProperty.

```yaml
Type: System.Management.Automation.PSObject
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: FromObjectList
  Position: Named
  IsRequired: true
  ValueFromPipeline: true
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -KeyProperty

The property name whose value is used as the dictionary key.
The value
is trimmed of whitespace and converted to lowercase before insertion.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: FromObjectList
  Position: Named
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

### System.Management.Automation.PSObject



## OUTPUTS

### System.Collections.Generic.Dictionary[string



## NOTES

## RELATED LINKS



