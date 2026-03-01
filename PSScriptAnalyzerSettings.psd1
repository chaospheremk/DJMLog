@{
    Rules = @{
        PSAvoidUsingCmdletAliases              = @{ Enable = $true }
        PSUseApprovedVerbs                     = @{ Enable = $true }
        PSAvoidGlobalVars                      = @{ Enable = $true }
        PSUseDeclaredVarsMoreThanAssignments   = @{ Enable = $true }
    }
    ExcludeRules = @()
}
