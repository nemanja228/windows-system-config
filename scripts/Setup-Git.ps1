<#
.SYNOPSIS
    Install git, deploy the repo's .gitconfig, and set user.name/user.email.
    Fully idempotent.

.DESCRIPTION
    Three steps, each a no-op when already in the desired state:

      1. Install/upgrade git via winget. Skips winget call entirely if git
         is on PATH AND -Force is not set.

      2. Deploy profiles/git/.gitconfig to $HOME/.gitconfig by delegating
         to Install-Profiles.ps1 -Only git -NoInit. That helper preserves
         existing user.name/user.email via `git config --global --get` →
         restore-after-overwrite.

      3. Set/update global identity:
           - If -GitUserName / -GitUserEmail provided AND differ from
             current values, write via `git config --global`.
           - If not provided AND not currently set, prompt interactively.
           - If already set AND no params given, leave alone (silent).

    SSH key + GitHub registration is a separate concern — see
    scripts/New-GitHubSshProfile.ps1.

.PARAMETER GitUserName
    Optional. New value for user.name. Skipped if already matches.

.PARAMETER GitUserEmail
    Optional. New value for user.email. Skipped if already matches.

.PARAMETER Force
    Re-install git even if present; re-write gitconfig even if matches;
    re-set identity even if matches.

.EXAMPLE
    .\Setup-Git.ps1
    # Ensure git installed, ensure repo gitconfig deployed, leave identity
    # alone if already set, prompt if not.

.EXAMPLE
    .\Setup-Git.ps1 -GitUserName "Nemanja Raković" -GitUserEmail "me@example.com"
    # Set identity explicitly (no-op if same as current).

.EXAMPLE
    .\Setup-Git.ps1 -Force
    # Re-do every step regardless of current state.
#>
[CmdletBinding()]
param(
    [string]$GitUserName,
    [string]$GitUserEmail,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# =============================================================================
# Module
# =============================================================================

$scriptDir = $PSScriptRoot
$repoRoot  = Split-Path -Parent $scriptDir
$modulePath = Join-Path $repoRoot 'lib\WinSetup'

if (Get-Module -Name WinSetup) {
    Import-Module $modulePath -ErrorAction SilentlyContinue
} else {
    Import-Module $modulePath -Force
}

$init = Initialize-Logging -LogPrefix 'setup-git'

Write-Log -Level STEP -Message "==============================================="
Write-Log -Level STEP -Message " Setup-Git"
Write-Log -Level STEP -Message "==============================================="
Write-Log -Level INFO -Message "Repo:   $repoRoot"
if ($GitUserName)  { Write-Log -Level INFO -Message "Name:   $GitUserName" }
if ($GitUserEmail) { Write-Log -Level INFO -Message "Email:  $GitUserEmail" }
if ($Force)        { Write-Log -Level WARN -Message "FLAG:   -Force" }

# =============================================================================
# 1. Install/upgrade git
# =============================================================================

Invoke-Step -Name "Install/upgrade git" -Tags @('git') -ContinueOnError -Action {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git -and -not $Force) {
        $version = (& git --version 2>$null) -join ' '
        Write-Log -Level DEBUG -Message "  $version at $($git.Source) — skip (use -Force to re-install)"
        return
    }

    if ($git) {
        Write-Log -Level INFO -Message "  -Force: re-running winget upgrade"
        & winget upgrade --id Git.Git -e --accept-source-agreements --accept-package-agreements --silent
    } else {
        Write-Log -Level INFO -Message "  Installing Git.Git via winget"
        & winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements --silent
        # Refresh PATH for the rest of this session so git is callable below.
        $env:PATH = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
    }
}

# =============================================================================
# 2. Deploy gitconfig (identity preserved)
# =============================================================================

Invoke-Step -Name "Deploy gitconfig from repo (preserve identity)" -Tags @('git') -ContinueOnError -Action {
    $installProfiles = Join-Path $scriptDir 'Install-Profiles.ps1'
    if (-not (Test-Path $installProfiles)) {
        throw "Cannot find Install-Profiles.ps1 at $installProfiles"
    }
    # -NoInit so the called script shares THIS session's logger.
    & $installProfiles -NoInit -Only git -Force:$Force
}

# =============================================================================
# 3. Set / update identity
# =============================================================================

Invoke-Step -Name "Set git identity" -Tags @('git') -ContinueOnError -Action {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) {
        throw "git not on PATH — install step failed?"
    }

    $currentName  = (& git config --global --get user.name  2>$null) -join ''
    $currentEmail = (& git config --global --get user.email 2>$null) -join ''

    $desiredName  = $GitUserName
    $desiredEmail = $GitUserEmail

    # Prompt only if both unset (no param + no current value).
    if (-not $desiredName -and -not $currentName) {
        $desiredName = Read-Host "Git user.name"
    }
    if (-not $desiredEmail -and -not $currentEmail) {
        $desiredEmail = Read-Host "Git user.email"
    }

    if ($desiredName -and ($Force -or $desiredName -ne $currentName)) {
        & git config --global user.name $desiredName | Out-Null
        Write-Log -Level SUCCESS -Message "  user.name  = $desiredName"
    } elseif ($currentName) {
        Write-Log -Level DEBUG -Message "  user.name  unchanged: $currentName"
    }

    if ($desiredEmail -and ($Force -or $desiredEmail -ne $currentEmail)) {
        & git config --global user.email $desiredEmail | Out-Null
        Write-Log -Level SUCCESS -Message "  user.email = $desiredEmail"
    } elseif ($currentEmail) {
        Write-Log -Level DEBUG -Message "  user.email unchanged: $currentEmail"
    }
}

# =============================================================================
# Wrap up
# =============================================================================

Show-Summary

$failed = (Get-StepSummary | Where-Object { -not $_.Success }).Count
if ($failed -eq 0) {
    Write-Log -Level SUCCESS -Message "Setup-Git complete."
    Write-Log -Level INFO -Message ""
    Write-Log -Level INFO -Message "Next: add an SSH key for GitHub via"
    Write-Log -Level INFO -Message "  .\scripts\New-GitHubSshProfile.ps1 -Email '<your-email>'"
    exit 0
} else {
    Write-Log -Level WARN -Message "$failed step(s) failed."
    exit 1
}
