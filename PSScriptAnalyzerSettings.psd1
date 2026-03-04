@{
    # Run all default rules except the ones excluded below.
    # The four rules in the Rules block are enabled by default; the block
    # is kept here as documentation of the rules we explicitly care about.
    Rules = @{
        PSAvoidUsingCmdletAliases            = @{ Enable = $true }
        PSUseApprovedVerbs                   = @{ Enable = $true }
        PSAvoidGlobalVars                    = @{ Enable = $true }
        PSUseDeclaredVarsMoreThanAssignments = @{ Enable = $true }
    }

    ExcludeRules = @(
        # UTF-8 without BOM is valid; em dashes in help comments are intentional.
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
