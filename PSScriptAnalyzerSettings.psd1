@{
    Severity = @('Warning', 'Error')

    # Run all default rules except the ones excluded below. The four rules
    # below are explicitly raised to Severity = 'Error' (Phase 2 / M12) so
    # CI fails on style regressions that previously slipped through as warnings.
    Rules = @{
        PSAvoidUsingCmdletAliases            = @{ Enable = $true; Severity = 'Error' }
        PSUseApprovedVerbs                   = @{ Enable = $true; Severity = 'Error' }
        PSAvoidGlobalVars                    = @{ Enable = $true; Severity = 'Error' }
        PSUseDeclaredVarsMoreThanAssignments = @{ Enable = $true }
    }

    ExcludeRules = @(
        # UTF-8 without BOM is our standard; exclude the rule that enforces BOM.
        'PSUseBOMForUnicodeEncodedFile'

        # Write-Host is intentional for -Colorize console output and CSV confirmation.
        'PSAvoidUsingWriteHost'

        # Set-DJMLogConfig modifies module-scoped variables, not system state.
        # ShouldProcess overhead is not warranted here.
        'PSUseShouldProcessForStateChangingFunctions'

        # Read-DJMLog legitimately returns List[string] (-Raw) or List[PSObject].
        # Declaring both in OutputType adds noise without value.
        'PSUseOutputTypeCorrectly'

        # Test files use ConvertTo-SecureString -AsPlainText to validate SecureString handling.
        'PSAvoidUsingConvertToSecureStringWithPlainText'
    )
}
