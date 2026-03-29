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
    CoverageThreshold = 50
    CoverageFormat   = 'JaCoCo'
}
