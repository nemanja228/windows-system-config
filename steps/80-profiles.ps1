# =============================================================================
# 80 — Deploy user profile files via scripts/Install-Profiles.ps1
#
# Tags: profiles  (plus per-category sub-tags: git, pwsh, omp, wt, fonts, ahk)
#
# Folds Install-Profiles.ps1's six categories into the bootstrap run. The
# inner script is invoked with -NoInit so it shares this session's logger;
# each of its six Invoke-Step calls lands in the bootstrap summary table
# as its own row.
#
# Run standalone (without bootstrap) via:
#   .\scripts\Install-Profiles.ps1
# That path keeps full standalone behaviour (own log file, header, summary).
# =============================================================================

$installProfiles = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\Install-Profiles.ps1'

if (-not (Test-Path -LiteralPath $installProfiles)) {
    Invoke-Step -Name "Deploy profiles" -Tags @('profiles') -ContinueOnError -Action {
        throw "Install-Profiles.ps1 not found at $installProfiles"
    }
    return
}

# Inner script uses -SkipOnDryRun in each of its six Invoke-Step calls, so
# bootstrap's -DryRun/-Verify is honoured automatically.
& $installProfiles -NoInit
