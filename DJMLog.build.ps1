#Requires -Version 7.0
#Requires -Modules InvokeBuild

<#
.SYNOPSIS
    Build script for the DJMLog module. Run with: Invoke-Build [Task] [-Configuration <Debug|Release>]
#>

[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string] $Configuration = 'Debug',

    [string] $Version
)

# --- Config -----------------------------------------------------------------

$Config       = Import-PowerShellDataFile "$PSScriptRoot/build.config.psd1"
$ModuleName   = $Config.ModuleName
$ManifestPath = Join-Path $PSScriptRoot $Config.ManifestPath
$TestsDir     = Join-Path $PSScriptRoot $Config.TestsDir
$DocsDir      = Join-Path $PSScriptRoot $Config.DocsDir
$OutputDir    = Join-Path $PSScriptRoot $Config.OutputDir
$AcrRepo      = $Config.AcrRepoName
$PackageDir   = Join-Path $OutputDir $ModuleName

# --- Tasks ------------------------------------------------------------------

task Clean {
    if (Test-Path $OutputDir) { Remove-Item $OutputDir -Recurse -Force }
    New-Item $OutputDir -ItemType Directory | Out-Null
}

task Lint {
    # Scan module source directories — excludes DJMLog.build.ps1 (Invoke-Build DSL aliases
    # like task/assert/exec trigger PSAvoidUsingCmdletAliases false positives)
    $scanPaths = @(
        Join-Path $PSScriptRoot $Config.PublicDir
        Join-Path $PSScriptRoot $Config.PrivateDir
        Join-Path $PSScriptRoot 'scripts'
        $ManifestPath
        Join-Path $PSScriptRoot "$ModuleName.psm1"
    ) | Where-Object { Test-Path $_ }

    $settingsPath = Join-Path $PSScriptRoot $Config.PSSASettingsPath
    $results = foreach ($scanPath in $scanPaths) {
        $pssaParams = @{
            Path     = $scanPath
            Recurse  = $true
            Settings = $settingsPath
        }
        Invoke-ScriptAnalyzer @pssaParams
    }
    if ($results) {
        foreach ($r in $results) {
            Write-Warning "[$($r.Severity)] $($r.RuleName) — $($r.ScriptName):$($r.Line)"
        }
        throw "PSScriptAnalyzer found $($results.Count) issue(s). Fix before proceeding."
    }
}

task Test {
    # Synchronous-write mode for v1.x test compatibility — Write-DJMLog will
    # block until the entry is processed by the writer runspace. Stress tests
    # that exercise the async path explicitly clear this in their BeforeAll.
    $env:DJMLOG_SYNC_WRITES = '1'

    $pesterConfig = New-PesterConfiguration
    $pesterConfig.Run.Path = $TestsDir
    $pesterConfig.Run.PassThru = $true
    $pesterConfig.Output.Verbosity = 'Detailed'
    # Exclude the long-running async stress test from the default suite
    # (the suite would take 30+ s otherwise). Run via `Invoke-Build TestStress`.
    $pesterConfig.Filter.ExcludeTag = @('Stress')

    $pesterConfig.TestResult.Enabled = $true
    $pesterConfig.TestResult.OutputFormat = 'JUnitXml'
    $pesterConfig.TestResult.OutputPath = Join-Path $PSScriptRoot 'TestResults.xml'

    $pesterConfig.CodeCoverage.Enabled = ($Configuration -eq 'Release')
    $pesterConfig.CodeCoverage.OutputFormat = $Config.CoverageFormat
    $pesterConfig.CodeCoverage.OutputPath = Join-Path $PSScriptRoot 'CoverageResults.xml'
    # Build the coverage path list as individual files so we can exclude
    # specific ones. Start-DJMWriter.ps1's bulk is the writer-loop scriptblock
    # body that runs in a *different* runspace; Pester's profiler-based
    # coverage cannot account for execution there. Including it in the
    # denominator without any way to credit execution skews coverage downward
    # by ~300 lines. The function-level surface (Start-/Stop-/Push-/Wait-/
    # Update-DJMWriter*, Add-DJMWriterError) is exercised by the rest of the
    # suite; the scriptblock body is exercised by the AsyncWriter stress test.
    $excludeNames = @('Start-DJMWriter.ps1')
    $coveragePaths = [System.Collections.Generic.List[string]]::new()
    foreach ($folder in $Config.CoveragePaths) {
        $abs = Join-Path $PSScriptRoot $folder
        if (Test-Path $abs) {
            foreach ($file in Get-ChildItem -Path $abs -Filter '*.ps1' -Recurse) {
                if ($excludeNames -notcontains $file.Name) {
                    [void]$coveragePaths.Add($file.FullName)
                }
            }
        }
    }
    $pesterConfig.CodeCoverage.Path = $coveragePaths.ToArray()
    # Profiler-based coverage (UseBreakpoints=$false) emits per-statement hit
    # counts in the JaCoCo report, giving us branch-level visibility on top of
    # line coverage. Pester 5 does not surface a separate branch percentage;
    # the JaCoCo XML carries the branch counters consumers can chart on.
    $pesterConfig.CodeCoverage.UseBreakpoints = $false

    $result = Invoke-Pester -Configuration $pesterConfig
    assert ($result.FailedCount -eq 0) "Pester: $($result.FailedCount) test(s) failed."

    if ($Configuration -eq 'Release') {
        $threshold = $Config.CoverageThreshold
        $coveragePct = [math]::Round($result.CodeCoverage.CoveragePercent, 2)
        Write-Build Green "Code coverage: $coveragePct% (threshold: $threshold%)"
        assert ($coveragePct -ge $threshold) "Coverage $coveragePct% is below the $threshold% threshold."
    }
}

task Docs {
    Import-Module $ManifestPath -Force
    Import-Module Microsoft.PowerShell.PlatyPS

    if (-not (Test-Path $DocsDir)) {
        New-Item -ItemType Directory -Path $DocsDir -Force | Out-Null
    }

    # Generate markdown for each exported command
    $commands = Get-Command -Module $ModuleName
    foreach ($cmd in $commands) {
        $result = New-MarkdownCommandHelp -Command $cmd -OutputFolder $DocsDir -Force
        # PlatyPS v2 nests under a module subfolder — flatten to docs/commands/
        if ($result.Directory.Name -ne (Split-Path $DocsDir -Leaf)) {
            Move-Item -Path $result.FullName -Destination $DocsDir -Force
        }
    }

    # Clean up the module subfolder if empty
    $subDir = Join-Path $DocsDir $ModuleName
    if ((Test-Path $subDir) -and (Get-ChildItem $subDir | Measure-Object).Count -eq 0) {
        Remove-Item $subDir -Force
    }

    # Post-process: strip PlatyPS v2 placeholder text, normalize date stamps and line endings.
    # Line-ending normalization (CRLF → LF) ensures committed docs match fresh CI generation
    # where actions/checkout sets core.autocrlf=false (LF checkout) but PlatyPS writes CRLF.
    foreach ($filePath in (Get-ChildItem $DocsDir -Filter *.md).FullName) {
        $content = [System.IO.File]::ReadAllText($filePath)
        $cleaned = $content -replace '(?m)^This cmdlet has the following aliases,\s*\r?\n\s*\{\{Insert list of aliases\}\}\s*$', 'None.'
        $cleaned = $cleaned -replace '\{\{\s*Fill in the related links here\s*\}\}', ''
        $cleaned = $cleaned -replace '\{\{[^}]+\}\}', ''
        # PlatyPS embeds ms.date with today's date — normalize to prevent cross-day diffs
        $cleaned = $cleaned -replace '(?m)^ms\.date:\s*\d{2}/\d{2}/\d{4}', 'ms.date: 01/01/1970'
        $cleaned = $cleaned -replace '\r\n', "`n"
        [System.IO.File]::WriteAllText($filePath, $cleaned)
    }

    # Generate index page
    $index = [System.Text.StringBuilder]::new()
    [void]$index.AppendLine('# Command Reference')
    [void]$index.AppendLine()
    [void]$index.AppendLine('| Command | Description |')
    [void]$index.AppendLine('|---------|-------------|')
    foreach ($cmd in $commands) {
        $help = Get-Help $cmd.Name
        $synopsis = ($help.Synopsis -split "`n")[0].Trim().TrimEnd('.')
        [void]$index.AppendLine("| [$($cmd.Name)]($($cmd.Name).md) | $synopsis |")
    }
    [void]$index.AppendLine()
    $indexContent = $index.ToString() -replace '\r\n', "`n"
    [System.IO.File]::WriteAllText((Join-Path $DocsDir 'index.md'), $indexContent)

    Remove-Module $ModuleName -Force
    Write-Build Green "Documentation generated for $($commands.Count) commands"
}

task AssertDocsClean {
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "docs-check-$(New-Guid)"
    New-Item $tempDir -ItemType Directory | Out-Null

    try {
        Import-Module $ManifestPath -Force
        Import-Module Microsoft.PowerShell.PlatyPS

        # Generate fresh docs to temp directory
        $commands = Get-Command -Module $ModuleName
        foreach ($cmd in $commands) {
            $result = New-MarkdownCommandHelp -Command $cmd -OutputFolder $tempDir -Force
            if ($result.Directory.Name -ne (Split-Path $tempDir -Leaf)) {
                Move-Item -Path $result.FullName -Destination $tempDir -Force
            }
        }

        # Clean up module subfolder if empty
        $subDir = Join-Path $tempDir $ModuleName
        if ((Test-Path $subDir) -and (Get-ChildItem $subDir | Measure-Object).Count -eq 0) {
            Remove-Item $subDir -Force
        }

        # Identical post-processing as the Docs task, plus line-ending normalization
        # (actions/checkout on Windows sets core.autocrlf=false → LF checkout,
        #  but PlatyPS generates CRLF — normalize both sides to LF before hashing)
        foreach ($filePath in (Get-ChildItem $tempDir -Filter *.md).FullName) {
            $content = [System.IO.File]::ReadAllText($filePath)
            $cleaned = $content -replace '(?m)^This cmdlet has the following aliases,\s*\r?\n\s*\{\{Insert list of aliases\}\}\s*$', 'None.'
            $cleaned = $cleaned -replace '\{\{\s*Fill in the related links here\s*\}\}', ''
            $cleaned = $cleaned -replace '\{\{[^}]+\}\}', ''
            $cleaned = $cleaned -replace '(?m)^ms\.date:\s*\d{2}/\d{2}/\d{4}', 'ms.date: 01/01/1970'
            $cleaned = $cleaned -replace '\r\n', "`n"
            [System.IO.File]::WriteAllText($filePath, $cleaned)
        }

        # Generate index page to temp
        $index = [System.Text.StringBuilder]::new()
        [void]$index.AppendLine('# Command Reference')
        [void]$index.AppendLine()
        [void]$index.AppendLine('| Command | Description |')
        [void]$index.AppendLine('|---------|-------------|')
        foreach ($cmd in $commands) {
            $help = Get-Help $cmd.Name
            $synopsis = ($help.Synopsis -split "`n")[0].Trim().TrimEnd('.')
            [void]$index.AppendLine("| [$($cmd.Name)]($($cmd.Name).md) | $synopsis |")
        }
        [void]$index.AppendLine()
        $indexContent = $index.ToString() -replace '\r\n', "`n"
        [System.IO.File]::WriteAllText((Join-Path $tempDir 'index.md'), $indexContent)

        Remove-Module $ModuleName -Force

        # Normalize committed docs to a temp copy so ms.date differences don't cause false failures
        $committedTemp = Join-Path ([System.IO.Path]::GetTempPath()) "docs-committed-$(New-Guid)"
        New-Item $committedTemp -ItemType Directory | Out-Null
        if (Test-Path $DocsDir) {
            $committedMd = Get-ChildItem $DocsDir -Filter *.md
            if ($committedMd) {
                Copy-Item $committedMd.FullName $committedTemp
            }
        }
        foreach ($filePath in (Get-ChildItem $committedTemp -Filter *.md).FullName) {
            $content = [System.IO.File]::ReadAllText($filePath)
            $cleaned = $content -replace '(?m)^ms\.date:\s*\d{2}/\d{2}/\d{4}', 'ms.date: 01/01/1970'
            $cleaned = $cleaned -replace '\r\n', "`n"
            [System.IO.File]::WriteAllText($filePath, $cleaned)
        }

        # Compare (hash, filename) tuples so renamed files are caught
        $committedFiles = Get-ChildItem $committedTemp -Filter *.md |
            Get-FileHash |
            ForEach-Object { "$($_.Hash):$($_.Path | Split-Path -Leaf)" } |
            Sort-Object
        $freshFiles = Get-ChildItem $tempDir -Filter *.md |
            Get-FileHash |
            ForEach-Object { "$($_.Hash):$($_.Path | Split-Path -Leaf)" } |
            Sort-Object

        if (-not $committedFiles -and -not $freshFiles) {
            Write-Build Yellow "Warning: No docs found in either committed or generated directories."
            return
        }
        if (-not $committedFiles) {
            throw "No committed docs found in '$DocsDir'. Run 'Invoke-Build Docs' locally and commit the result."
        }
        if (-not $freshFiles) {
            throw "Committed docs exist but fresh generation produced nothing. Check module import and PlatyPS."
        }

        $diff = Compare-Object $committedFiles $freshFiles
        if ($diff) {
            $added   = ($diff | Where-Object SideIndicator -eq '=>').InputObject
            $removed = ($diff | Where-Object SideIndicator -eq '<=').InputObject
            if ($added)   { Write-Build Red "New/changed in fresh generation: $($added -join ', ')" }
            if ($removed) { Write-Build Red "Missing from fresh generation: $($removed -join ', ')" }
            throw "Committed docs are out of date. Run 'Invoke-Build Docs' locally and commit the result."
        }
    }
    finally {
        Remove-Item $tempDir -Recurse -Force
        if ($committedTemp -and (Test-Path $committedTemp)) {
            Remove-Item $committedTemp -Recurse -Force
        }
    }
}

task BumpVersion {
    $manifest = Import-PowerShellDataFile $ManifestPath
    $version = [version] $manifest.ModuleVersion
    $script:NewVersion = [version]::new($version.Major, $version.Minor, $version.Build + 1)
    Write-Build Green "Bumping version: $version -> $script:NewVersion"
    Update-ModuleManifest -Path $ManifestPath -ModuleVersion $script:NewVersion
}

task Pack Clean, {
    $packDest = Join-Path $OutputDir $ModuleName
    New-Item $packDest -ItemType Directory -Force | Out-Null

    $itemsToCopy = @(
        $ManifestPath
        (Join-Path $PSScriptRoot "$ModuleName.psm1")
        (Join-Path $PSScriptRoot $Config.PublicDir)
        (Join-Path $PSScriptRoot $Config.PrivateDir)
    )

    foreach ($item in $itemsToCopy) {
        if (Test-Path $item) {
            Copy-Item $item $packDest -Recurse -Force
        }
    }

    # Include MAML help if it exists
    $mamlDir = Join-Path $PSScriptRoot 'en-US'
    if (Test-Path $mamlDir) {
        Copy-Item $mamlDir (Join-Path $packDest 'en-US') -Recurse -Force
    }

    Write-Build Green "Packed $ModuleName to $packDest"
}

# --- Release tasks ------------------------------------------------------------

task SetVersion {
    assert $Version "Version parameter is required for SetVersion task."
    Write-Build Green "Setting version to $Version"
    Update-ModuleManifest -Path $ManifestPath -ModuleVersion $Version
}

task RegisterAcr {
    $acrServer = $env:ACR_LOGIN_SERVER
    assert $acrServer "ACR_LOGIN_SERVER environment variable is not set."

    $repoParams = @{
        Name    = $AcrRepo
        Uri     = "https://$acrServer"
        Trusted = $true
        Force   = $true
    }
    Register-PSResourceRepository @repoParams
    Write-Build Green "Registered PSResource repository '$AcrRepo' at https://$acrServer"
}

task Publish {
    assert (Test-Path $PackageDir) "Package directory '$PackageDir' not found. Run Pack first."

    $publishParams = @{
        Path       = $PackageDir
        Repository = $AcrRepo
    }
    Publish-PSResource @publishParams
    Write-Build Green "Published $ModuleName to $AcrRepo"
}

task TestStress {
    $pesterConfig = New-PesterConfiguration
    $pesterConfig.Run.Path = (Join-Path $TestsDir 'StressTests')
    $pesterConfig.Run.PassThru = $true
    $pesterConfig.Output.Verbosity = 'Detailed'
    $pesterConfig.Filter.Tag = @('Stress')

    $result = Invoke-Pester -Configuration $pesterConfig
    assert ($result.FailedCount -eq 0) "StressTests: $($result.FailedCount) test(s) failed."
}

task Release Lint, Test, AssertDocsClean, SetVersion, Pack, RegisterAcr, Publish

# --- Default ------------------------------------------------------------------

task Build Clean, Lint, Test, Docs
task . Build
