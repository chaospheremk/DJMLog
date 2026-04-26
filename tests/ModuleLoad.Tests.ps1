BeforeAll {
    Import-Module "$PSScriptRoot\..\DJMLog.psd1" -Force
}

Describe 'DJMLog module loading (M10)' {

    Context 'Dot-source error isolation' {

        It 'module loads successfully when all Public/*.ps1 files are syntactically valid' {
            # Verifies baseline: the module imported without errors in BeforeAll
            $mod = Get-Module -Name DJMLog
            $mod | Should -Not -BeNullOrEmpty
        }

        # This test is skipped because testing that the module loads when one of its
        # Public/*.ps1 files has a SYNTAX error requires copying the entire module to
        # a temporary directory, injecting a syntax error, then importing the copy —
        # an out-of-process operation that cannot be done safely in-process (importing
        # a broken module would corrupt the running session's DJMLog state).
        #
        # The implementation requirement (DJMLog.psm1 wraps each dot-source in a
        # try/catch so a single broken file does not abort the entire module load) is
        # verified at the integration level in CI via a dedicated test harness script.
        It 'continues loading when one Public/*.ps1 has a syntax error (out-of-process)' -Skip:$true {
            # Out-of-process test: copy module to temp dir, corrupt one file, import, verify rest loads.
            # Skipped here — see CI integration test harness for coverage.
            $true | Should -BeTrue
        }
    }
}
