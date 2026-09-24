# PSScriptAnalyzer settings for the install-matrix `windows` job, which lints every
# tracked .ps1 (install.ps1, windows/powershell/profile.ps1) at Warning and Error.
#
# Each exclusion below is a deliberate design choice, not a finding waved through.
# Adding a rule here needs the same kind of reason; fix new findings otherwise.
@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # install.ps1 is an interactive installer whose output is console status
        # text for a person to read, colored per step. Write-Output would mix it
        # into the pipeline, which is wrong for a script run as `pwsh -File`.
        'PSAvoidUsingWriteHost'

        # Set-DotLink / Set-Stub / Update-SessionPath are private helpers of
        # install.ps1. The script's own -DryRun switch is its preview mode, and
        # CI proves it mutation-free; -WhatIf/-Confirm plumbing on each helper
        # would duplicate it.
        'PSUseShouldProcessForStateChangingFunctions'

        # profile.ps1 runs `starship init` and `zoxide init` output through
        # Invoke-Expression. That is the documented init idiom for both tools,
        # and the code comes from binaries installed by winget, not user input.
        'PSAvoidUsingInvokeExpression'
    )
}
