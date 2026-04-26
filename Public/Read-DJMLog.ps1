function Read-DJMLog {
    <#
    .SYNOPSIS
    Reads and filters a JSONL log file produced by Write-DJMLog.

    .DESCRIPTION
    Streams the target file line by line using [System.IO.File]::ReadLines,
    keeping memory usage flat regardless of file size. Each line is parsed
    as a JSON object. Lines that cannot be parsed, have an invalid timestamp,
    or are missing Level or Message are skipped with a warning.

    Filtering is applied before object construction. All active filters must
    match for an entry to be included. -First and -Last are applied after all
    other filters have been evaluated. -First and -Last cannot be combined;
    if both are supplied, -First is honoured and a warning is emitted.

    Metadata flattening:
        Nested Metadata properties are recursively promoted to top-level
        columns using underscore-separated key paths. Flattening descends
        through all levels of nesting. For example:
            Metadata.Error.Message      -> Error_Message
            Metadata.Http.Response.Code -> Http_Response_Code

    Column normalisation:
        All returned objects are padded with $null for any column not present
        in that specific entry, so every object in the output shares an
        identical property set. Column order reflects first-seen insertion
        order across the result set after -First or -Last slicing.

    Output timestamps:
        LocalTime — entry timestamp converted to the local timezone
        UtcTime   — entry timestamp in UTC

    Output behaviour:
        By default, PSCustomObjects are emitted to the pipeline. When
        -Colorize, -ExportCsv, or -OutGridView are specified, pipeline output
        is suppressed unless -PassThru is also present. When -Raw is specified,
        the unmodified JSON strings are emitted to the pipeline instead of
        objects. -Colorize, -ExportCsv, and -OutGridView still operate on the
        parsed objects regardless of -Raw.

    .PARAMETER LogPath
    Path to the JSONL file to read. When omitted, the module-level default
    configured by Set-DJMLogConfig is used. Falls back to log.jsonl in the current
    working directory if no default has been set.

    .PARAMETER Level
    Restricts output to entries matching one or more severity levels.
    Accepts an array. Case-insensitive. When omitted, all levels are returned.

    .PARAMETER CorrelationId
    Restricts output to entries whose CorrelationId exactly matches the
    provided string. Case-sensitive.

    .PARAMETER MessageContains
    Restricts output to entries whose Message field matches the given wildcard
    pattern. Equivalent to -like "*<value>*".

    .PARAMETER Since
    Restricts output to entries with a UTC timestamp at or after this value.
    The provided datetime is converted to UTC before comparison.

    .PARAMETER Until
    Restricts output to entries with a UTC timestamp at or before this value.
    The provided datetime is converted to UTC before comparison.

    .PARAMETER First
    Returns only the first N entries from the filtered result set. Cannot be
    combined with -Last.

    .PARAMETER Last
    Returns only the last N entries from the filtered result set. Cannot be
    combined with -First.

    .PARAMETER Colorize
    Writes a formatted summary of each matching entry to the host using
    colour-coded output: ERROR=Red, WARN=Yellow, DEBUG=DarkGray, INFO=Gray.
    Output format: yyyy-MM-dd HH:mm:ss [LVL] Message (local time).
    Suppresses pipeline output unless -PassThru is also specified.

    .PARAMETER ExportCsv
    Exports all matching results to a CSV file at -CsvPath after processing
    completes. Suppresses pipeline output unless -PassThru is also specified.

    .PARAMETER CsvPath
    Destination path for the CSV export. Only used when -ExportCsv is
    specified. Defaults to log.csv in the current working directory.

    .PARAMETER OutGridView
    Sends all matching results to Out-GridView for interactive inspection.
    Windows only. A warning is emitted and the switch is ignored on non-Windows
    platforms. Suppresses pipeline output unless -PassThru is also specified.

    .PARAMETER Raw
    Emits the unmodified JSON strings from the file instead of PSCustomObjects.
    Filtering still applies. -Colorize, -ExportCsv, and -OutGridView continue
    to operate on the parsed objects regardless of -Raw.

    .PARAMETER PassThru
    When specified alongside -Colorize, -ExportCsv, or -OutGridView, also
    emits result objects to the pipeline. When -Raw is also set, emits JSON
    strings. Has no effect when none of those switches are present, as
    pipeline output is the default behaviour in that case.

    .OUTPUTS
    PSCustomObject by default. String when -Raw is specified.

    .EXAMPLE
    # Return all ERROR entries as objects
    $errors = Read-DJMLog -Level ERROR
    $errors | Select-Object LocalTime, Message, Error_Message

    .EXAMPLE
    # Colorized console view filtered by level and time window
    Read-DJMLog -Level WARN, ERROR -Since (Get-Date).AddHours(-4) -Colorize

    .EXAMPLE
    # Filter by message content and export to CSV
    Read-DJMLog -MessageContains 'provisioning' -ExportCsv -CsvPath C:\Reports\provision.csv

    .EXAMPLE
    # Colorize to console and also capture results for further processing
    $results = Read-DJMLog -Level ERROR -Colorize -PassThru
    $results | Group-Object CorrelationId | Where-Object { $_.Count -gt 1 }

    .EXAMPLE
    # Retrieve all entries for a specific operation by correlation ID
    Read-DJMLog -CorrelationId $cid | Format-Table LocalTime, Level, Message

    .EXAMPLE
    # Show the 20 most recent entries interactively on Windows
    Read-DJMLog -Last 20 -OutGridView

    .EXAMPLE
    # Emit raw JSON strings for forwarding or external processing
    Read-DJMLog -Level ERROR -Raw | Set-Content -LiteralPath C:\export\errors.jsonl
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    [OutputType([string[]])]
    param (
        [string]$LogPath,

        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG', IgnoreCase = $true)]
        [string[]]$Level,

        [string]$CorrelationId,

        [string]$MessageContains,

        [datetime]$Since,

        [datetime]$Until,

        [int]$First,

        [int]$Last,

        [switch]$Colorize,

        [switch]$ExportCsv,

        [string]$CsvPath = "$(Get-Location)\log.csv",

        [switch]$OutGridView,

        [switch]$Raw,

        [switch]$PassThru
    )

    begin {
        # Resolve effective log path: explicit parameter > module default > cwd fallback
        if (-not $LogPath) {
            $LogPath = if ($script:DefaultLogPath) { $script:DefaultLogPath }
                       else { "$(Get-Location)\log.jsonl" }
        }

        $earlyExit = $false

        if (-not (Test-Path -LiteralPath $LogPath)) {
            Write-Warning "Read-DJMLog: log file not found at path: $LogPath"
            $earlyExit = $true
            return
        }

        if ($PSBoundParameters.ContainsKey('First') -and $PSBoundParameters.ContainsKey('Last')) {
            Write-Warning "Read-DJMLog: -First and -Last cannot be combined. -First will be applied."
        }

        if ($OutGridView -and -not $IsWindows) {
            Write-Warning "Read-DJMLog: -OutGridView is only supported on Windows."
            $OutGridView = $false
        }

        $entryDictionaries = [System.Collections.Generic.List[System.Collections.Generic.Dictionary[string, PSObject]]]::new()
        $allKeys           = [System.Collections.Generic.List[string]]::new()
        $rawLines          = [System.Collections.Generic.List[string]]::new()

        $resolvedLogPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LogPath)
        $lines           = [System.IO.File]::ReadLines($resolvedLogPath)
    }

    process {
        if ($earlyExit) { return }

        foreach ($line in $lines) {
            try {
                $entry              = ConvertFrom-Json -InputObject $line -Depth 10
                $entryLevel         = $entry.Level.ToUpperInvariant()
                $entryMessage       = $entry.Message
                $entryCorrelationId = $entry.CorrelationId
            }
            catch {
                Write-Warning "Read-DJMLog: skipping invalid JSON line: $line"
                continue
            }

            try { $timestampUtc = [datetime]$entry.UtcTimestamp }
            catch {
                Write-Warning "Read-DJMLog: skipping line with invalid timestamp: $($entry.UtcTimestamp)"
                continue
            }

            if (-not $entryLevel -or -not $entryMessage) {
                Write-Warning "Read-DJMLog: skipping line missing Level or Message field."
                continue
            }

            $timestampLocal = $timestampUtc.ToLocalTime()

            if (
                ($Level          -and ($entryLevel -notin $Level)) -or
                ($CorrelationId  -and ($entryCorrelationId -ne $CorrelationId)) -or
                ($MessageContains -and ($entryMessage -notlike "*$MessageContains*")) -or
                ($Since -and $timestampUtc -lt $Since.ToUniversalTime()) -or
                ($Until -and $timestampUtc -gt $Until.ToUniversalTime())
            ) { continue }

            $entryDict = [System.Collections.Generic.Dictionary[string, PSObject]]::new()
            $entryDict['LocalTime']     = $timestampLocal
            $entryDict['UtcTime']       = $timestampUtc
            $entryDict['Level']         = $entryLevel
            $entryDict['Message']       = $entryMessage
            $entryDict['CorrelationId'] = $entryCorrelationId

            if ($entry.Metadata) {
                foreach ($property in $entry.Metadata.PSObject.Properties) {
                    Expand-MetadataValue -Prefix $property.Name -Value $property.Value -Target $entryDict
                }
            }

            $entryDictionaries.Add($entryDict)
            $rawLines.Add($line)
        }

        # Apply -First or -Last slicing before normalisation so allKeys reflects only returned entries
        if ($PSBoundParameters.ContainsKey('First') -and $entryDictionaries.Count -gt $First) {
            $entryDictionaries = $entryDictionaries.GetRange(0, $First)
            $rawLines          = $rawLines.GetRange(0, $First)
        }
        elseif ($PSBoundParameters.ContainsKey('Last') -and $entryDictionaries.Count -gt $Last) {
            $startIndex        = $entryDictionaries.Count - $Last
            $entryDictionaries = $entryDictionaries.GetRange($startIndex, $Last)
            $rawLines          = $rawLines.GetRange($startIndex, $Last)
        }

        # Colorize after slicing so only returned entries are printed
        if ($Colorize) {
            foreach ($entryDict in $entryDictionaries) {
                $levelAbbr = switch ($entryDict['Level']) {
                    'ERROR' { 'ERR' }
                    'WARN'  { 'WRN' }
                    'INFO'  { 'INF' }
                    'DEBUG' { 'DBG' }
                    default { $entryDict['Level'].Substring(0, [Math]::Min(3, $entryDict['Level'].Length)).ToUpperInvariant() }
                }

                $color = switch ($entryDict['Level']) {
                    'ERROR' { 'Red' }
                    'WARN'  { 'Yellow' }
                    'DEBUG' { 'DarkGray' }
                    default { 'Gray' }
                }

                $formattedLine = "{0} [{1}] {2}" -f $entryDict['LocalTime'].ToString("yyyy-MM-dd HH:mm:ss"), $levelAbbr, $entryDict['Message']
                Write-Host $formattedLine -ForegroundColor $color
            }
        }

        # Rebuild allKeys from the sliced set only
        foreach ($entryDict in $entryDictionaries) {
            foreach ($key in $entryDict.Keys) {
                if (-not $allKeys.Contains($key)) { $null = $allKeys.Add($key) }
            }
        }

        # Normalise: pad missing keys and build ordered PSCustomObjects
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
