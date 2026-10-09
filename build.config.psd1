# Build configuration for DJMLog
# Consumed by DJMLog.build.ps1 — all paths are relative to the repo root.
@{
    ModuleName       = 'DJMLog'
    ManifestPath     = 'DJMLog.psd1'
    PublicDir        = 'Public'
    PrivateDir       = 'Private'
    TestsDir         = 'tests'
    DocsDir          = 'docs/commands'
    OutputDir        = 'output'
    PSSASettingsPath = 'PSScriptAnalyzerSettings.psd1'
    CoveragePaths    = @('Public', 'Private')
    CoverageThreshold = 70
    CoverageFormat   = 'JaCoCo'
    AcrRepoName      = 'HomeACR'
    # Exact PlatyPS version for Docs/AssertDocsClean and every workflow that installs it.
    # Minor releases change generated markdown (1.0.2+ drops [<CommonParameters>] from
    # syntax blocks), so local and CI output only match on one version.
    PlatyPSVersion   = '1.0.3'
}
