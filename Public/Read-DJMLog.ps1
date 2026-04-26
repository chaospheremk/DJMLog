function Read-DJMLog {
    <#
    .SYNOPSIS
    Reads and filters a JSONL log file produced by Write-DJMLog.

    .DESCRIPTION
    Streams the target file line by line using [System.IO.File]::ReadLines.

    Schema awareness (v2.0+):
        Read-DJMLog auto-detects per-entry SchemaVersion. When SchemaVersion is
        absent the entry is treated as schema v1; missing SeverityNumber is
        backfilled from the Level string. v2 entries pass through unchanged.

    Streaming (-Stream):
        Entries are emitted to the pipeline as parsed, without materialising
        the entire file. Filtering, flattening, and column normalisation are
        all per-entry. -First / -Last / -Colorize / -ExportCsv / -OutGridView
        require the non-stream mode and force materialisation when requested.

    .PARAMETER LogPath
    Path to the JSONL file to read. When omitted, the module-level default
    configured by Set-DJMLogConfig is used.

    .PARAMETER Level
    Restricts output to entries matching one or more severity levels.

    .PARAMETER CorrelationId
    Restricts output to entries whose CorrelationId exactly matches.

    .PARAMETER MessageContains
    Wildcard match against the Message field.

    .PARAMETER Since
    Restricts output to entries with a UTC timestamp at or after this value.

    .PARAMETER Until
    Restricts output to entries with a UTC timestamp at or before this value.

    .PARAMETER First
    Returns only the first N entries. Mutually exclusive with -Stream.

    .PARAMETER Last
    Returns only the last N entries. Mutually exclusive with -Stream.

    .PARAMETER Colorize
    Writes a formatted summary of each matching entry to the host using
    colour-coded output. Mutually exclusive with -Stream.

    .PARAMETER ExportCsv
    Exports all matching results to a CSV file. Mutually exclusive with -Stream.

    .PARAMETER CsvPath
    Destination for -ExportCsv. Defaults to log.csv in the current directory.

    .PARAMETER OutGridView
    Sends results to Out-GridView (Windows only). Mutually exclusive with -Stream.

    .PARAMETER Raw
    Emit unmodified JSON strings instead of objects.

    .PARAMETER PassThru
    With -Colorize/-ExportCsv/-OutGridView, also emit objects to the pipeline.

    .PARAMETER Stream
    Emit entries to the pipeline as they are parsed, without materialisation.
    Disables -First/-Last/-Colorize/-ExportCsv/-OutGridView.

    .OUTPUTS
    PSCustomObject by default. String when -Raw is specified.

    .EXAMPLE
    # Stream errors from a multi-GB file without loading it into memory
    Read-DJMLog -Stream -Level ERROR | Select-Object -First 100
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    [OutputType([string[]])]
    param (
        [string]$LogPath,

        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG', 'FATAL', IgnoreCase = $true)]
        [string[]]$Level,

        [string]$CorrelationId,

        [string]$MessageContains,

        [datetime]$Since,

        [datetime]$Until,

        [int]$First,

        [int]$Last,

        [switch]$Colorize,

        [switch]$ExportCsv,

        [string]$CsvPath,

        [switch]$OutGridView,

        [switch]$Raw,

        [switch]$PassThru,

        [switch]$Stream
    )

    begin {
        if (-not $LogPath) {
            $LogPath = if ($script:DefaultLogPath) { $script:DefaultLogPath }
                       else { "$(Get-Location)\log.jsonl" }
        }
        # Resolve CsvPath at call time so a caller who changed directory after
        # module load gets the expected default. (Default parameter values are
        # evaluated at function-definition time, so we cannot rely on them.)
        if (-not $CsvPath) { $CsvPath = "$(Get-Location)\log.csv" }

        $earlyExit = $false

        if (-not (Test-Path -LiteralPath $LogPath)) {
            Write-Warning "Read-DJMLog: log file not found at path: $LogPath"
            $earlyExit = $true
            return
        }

        if ($Stream -and ($PSBoundParameters.ContainsKey('First') -or $PSBoundParameters.ContainsKey('Last') -or
                         $Colorize -or $ExportCsv -or $OutGridView)) {
            Write-Warning "Read-DJMLog: -Stream is incompatible with -First / -Last / -Colorize / -ExportCsv / -OutGridView. Streaming disabled."
            $Stream = $false
        }

        if ($PSBoundParameters.ContainsKey('First') -and $PSBoundParameters.ContainsKey('Last')) {
            Write-Warning "Read-DJMLog: -First and -Last cannot be combined. -First will be applied."
        }

        if ($OutGridView -and -not $IsWindows) {
            Write-Warning "Read-DJMLog: -OutGridView is only supported on Windows."
            $OutGridView = $false
        }

        $resolvedLogPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LogPath)

        # Severity-from-level for v1 SeverityNumber backfill.
        $severityFromLevel = @{ DEBUG = 5; INFO = 9; WARN = 13; ERROR = 17; FATAL = 21 }

        $entryDictionaries = [System.Collections.Generic.List[System.Collections.Generic.Dictionary[string, PSObject]]]::new()
        $allKeys           = [System.Collections.Generic.List[string]]::new()
        $rawLines          = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($earlyExit) { return }

        # Inlined parse + filter loop. Inlining keeps Expand-MetadataValue
        # resolvable in the module's scope; a previous draft used a
        # GetNewClosure() scriptblock helper which rebound the scriptblock
        # out of the module's session state, breaking command resolution.
        if ($Stream) {
            foreach ($line in [System.IO.File]::ReadLines($resolvedLogPath)) {
                try {
                    $entry              = ConvertFrom-Json -InputObject $line -Depth 12
                    $entryLevel         = $entry.Level.ToUpperInvariant()
                    $entryMessage       = $entry.Message
                    $entryCorrelationId = $entry.CorrelationId
                }
                catch { Write-Warning "Read-DJMLog: skipping invalid JSON line: $line"; continue }
                try { $timestampUtc = [datetime]$entry.UtcTimestamp }
                catch { Write-Warning "Read-DJMLog: skipping line with invalid timestamp: $($entry.UtcTimestamp)"; continue }
                if (-not $entryLevel -or -not $entryMessage) { Write-Warning 'Read-DJMLog: skipping line missing Level or Message field.'; continue }
                if ($Level             -and ($entryLevel         -notin $Level))                  { continue }
                if ($CorrelationId     -and ($entryCorrelationId -ne $CorrelationId))             { continue }
                if ($MessageContains   -and ($entryMessage       -notlike "*$MessageContains*"))  { continue }
                if ($Since             -and ($timestampUtc       -lt $Since.ToUniversalTime()))   { continue }
                if ($Until             -and ($timestampUtc       -gt $Until.ToUniversalTime()))   { continue }

                if ($Raw) { $line; continue }

                $timestampLocal = $timestampUtc.ToLocalTime()
                $entryDict = [System.Collections.Generic.Dictionary[string, PSObject]]::new()
                $schema = if ($entry.PSObject.Properties['SchemaVersion']) { [string]$entry.SchemaVersion } else { '1' }
                $entryDict['SchemaVersion'] = $schema
                $entryDict['LocalTime']     = $timestampLocal
                $entryDict['UtcTime']       = $timestampUtc
                $entryDict['Level']         = $entryLevel
                $entryDict['Message']       = $entryMessage
                $entryDict['CorrelationId'] = $entryCorrelationId
                if ($entry.PSObject.Properties['SeverityNumber']) { $entryDict['SeverityNumber'] = [int]$entry.SeverityNumber }
                else { $entryDict['SeverityNumber'] = $severityFromLevel[$entryLevel] }
                foreach ($f in 'ActivityId', 'ParentActivityId', 'ActivityName') {
                    if ($entry.PSObject.Properties[$f]) { $entryDict[$f] = $entry.$f }
                }
                if ($entry.PSObject.Properties['Host'] -and $entry.Host) {
                    Expand-MetadataValue -Prefix 'Host' -Value $entry.Host -Target $entryDict
                }
                if ($entry.PSObject.Properties['Metadata'] -and $entry.Metadata) {
                    foreach ($p in $entry.Metadata.PSObject.Properties) {
                        Expand-MetadataValue -Prefix $p.Name -Value $p.Value -Target $entryDict
                    }
                }

                $obj = [ordered]@{}
                foreach ($key in $entryDict.Keys) { $obj[$key] = $entryDict[$key] }
                [PSCustomObject]$obj
            }
            return
        }

        # Non-stream: materialise
        foreach ($line in [System.IO.File]::ReadLines($resolvedLogPath)) {
            try {
                $entry              = ConvertFrom-Json -InputObject $line -Depth 12
                $entryLevel         = $entry.Level.ToUpperInvariant()
                $entryMessage       = $entry.Message
                $entryCorrelationId = $entry.CorrelationId
            }
            catch { Write-Warning "Read-DJMLog: skipping invalid JSON line: $line"; continue }
            try { $timestampUtc = [datetime]$entry.UtcTimestamp }
            catch { Write-Warning "Read-DJMLog: skipping line with invalid timestamp: $($entry.UtcTimestamp)"; continue }
            if (-not $entryLevel -or -not $entryMessage) { Write-Warning 'Read-DJMLog: skipping line missing Level or Message field.'; continue }
            if ($Level             -and ($entryLevel         -notin $Level))                  { continue }
            if ($CorrelationId     -and ($entryCorrelationId -ne $CorrelationId))             { continue }
            if ($MessageContains   -and ($entryMessage       -notlike "*$MessageContains*"))  { continue }
            if ($Since             -and ($timestampUtc       -lt $Since.ToUniversalTime()))   { continue }
            if ($Until             -and ($timestampUtc       -gt $Until.ToUniversalTime()))   { continue }

            $timestampLocal = $timestampUtc.ToLocalTime()
            $entryDict = [System.Collections.Generic.Dictionary[string, PSObject]]::new()
            $schema = if ($entry.PSObject.Properties['SchemaVersion']) { [string]$entry.SchemaVersion } else { '1' }
            $entryDict['SchemaVersion'] = $schema
            $entryDict['LocalTime']     = $timestampLocal
            $entryDict['UtcTime']       = $timestampUtc
            $entryDict['Level']         = $entryLevel
            $entryDict['Message']       = $entryMessage
            $entryDict['CorrelationId'] = $entryCorrelationId
            if ($entry.PSObject.Properties['SeverityNumber']) { $entryDict['SeverityNumber'] = [int]$entry.SeverityNumber }
            else { $entryDict['SeverityNumber'] = $severityFromLevel[$entryLevel] }
            foreach ($f in 'ActivityId', 'ParentActivityId', 'ActivityName') {
                if ($entry.PSObject.Properties[$f]) { $entryDict[$f] = $entry.$f }
            }
            if ($entry.PSObject.Properties['Host'] -and $entry.Host) {
                Expand-MetadataValue -Prefix 'Host' -Value $entry.Host -Target $entryDict
            }
            if ($entry.PSObject.Properties['Metadata'] -and $entry.Metadata) {
                foreach ($p in $entry.Metadata.PSObject.Properties) {
                    Expand-MetadataValue -Prefix $p.Name -Value $p.Value -Target $entryDict
                }
            }
            $entryDictionaries.Add($entryDict)
            $rawLines.Add($line)
        }

        if ($PSBoundParameters.ContainsKey('First') -and $entryDictionaries.Count -gt $First) {
            $entryDictionaries = $entryDictionaries.GetRange(0, $First)
            $rawLines          = $rawLines.GetRange(0, $First)
        }
        elseif ($PSBoundParameters.ContainsKey('Last') -and $entryDictionaries.Count -gt $Last) {
            $startIndex        = $entryDictionaries.Count - $Last
            $entryDictionaries = $entryDictionaries.GetRange($startIndex, $Last)
            $rawLines          = $rawLines.GetRange($startIndex, $Last)
        }

        if ($Colorize) {
            foreach ($entryDict in $entryDictionaries) {
                $abbr = switch ($entryDict['Level']) {
                    'FATAL' { 'FTL' } 'ERROR' { 'ERR' } 'WARN' { 'WRN' } 'INFO' { 'INF' } 'DEBUG' { 'DBG' }
                    default { ($entryDict['Level']).Substring(0, [Math]::Min(3, $entryDict['Level'].Length)).ToUpperInvariant() }
                }
                $color = switch ($entryDict['Level']) {
                    'FATAL' { 'Magenta' } 'ERROR' { 'Red' } 'WARN' { 'Yellow' } 'DEBUG' { 'DarkGray' } default { 'Gray' }
                }
                $formattedLine = "{0} [{1}] {2}" -f $entryDict['LocalTime'].ToString('yyyy-MM-dd HH:mm:ss'), $abbr, $entryDict['Message']
                Write-Host $formattedLine -ForegroundColor $color
            }
        }

        foreach ($entryDict in $entryDictionaries) {
            foreach ($key in $entryDict.Keys) {
                if (-not $allKeys.Contains($key)) { $null = $allKeys.Add($key) }
            }
        }

        $results = [System.Collections.Generic.List[PSObject]]::new()
        foreach ($entryDict in $entryDictionaries) {
            foreach ($key in $allKeys) {
                if (-not $entryDict.ContainsKey($key)) { $entryDict[$key] = $null }
            }
            $orderedHashtable = [ordered]@{}
            foreach ($key in $allKeys) { $orderedHashtable[$key] = $entryDict[$key] }
            $results.Add([PSCustomObject]$orderedHashtable)
        }

        if ($ExportCsv -and ($results.Count -gt 0)) {
            try {
                $results | Export-Csv -LiteralPath $CsvPath -Encoding ([System.Text.Encoding]::UTF8) -Force
                Write-Host "Read-DJMLog: exported $($results.Count) entries to '$CsvPath'" -ForegroundColor Green
            }
            catch {
                Write-Warning "Read-DJMLog: failed to export log to CSV: $_"
            }
        }

        if ($OutGridView -and ($results.Count -gt 0)) {
            $results | Out-GridView -Title "Log: $LogPath"
        }

        $suppressPipeline = $Colorize -or $ExportCsv -or $OutGridView
        if (-not $suppressPipeline -or $PassThru) {
            if ($Raw) { $rawLines } else { $results }
        }
    }
}
