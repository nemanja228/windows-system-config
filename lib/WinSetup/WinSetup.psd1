@{
    RootModule        = 'WinSetup.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '7e3a5f1b-8d2a-4c5e-9f6b-0a1b2c3d4e5f'
    Author            = 'Nemanja Rakovic'
    CompanyName       = 'win-setup'
    Copyright         = '(c) Nemanja Rakovic. All rights reserved.'
    Description       = 'Reusable helpers for win-setup bootstrap and post-install scripts: timestamped logging, tag-filtered step wrapper, resource path resolution, and per-value .reg import.'

    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'Initialize-Logging',
        'Set-LoggingFilter',
        'Write-Log',
        'Invoke-Step',
        'Show-Summary',
        'Get-StepSummary',
        'Get-ResourcePath',
        'Import-RegFilePerValue'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags       = @('win-setup', 'logging', 'windows', 'bootstrap')
            ProjectUri = 'https://github.com/nemanja228/windows-system-config'
        }
    }
}
