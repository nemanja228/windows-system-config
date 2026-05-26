# =============================================================================
# 85 - PowerShell modules consumed by the deployed profile
#
# Profile (profiles/powershell/Microsoft.PowerShell_profile.ps1) imports:
#   - PSReadLine       (ships with Windows / pwsh, no install)
#   - Terminal-Icons   (lazy-loaded on first `ls` -> needs install)
#   - z                (loaded on profile start -> needs install)
#
# CurrentUser scope: no elevation needed for the install itself.
# =============================================================================

Invoke-Step -Name "PS modules: trust PSGallery" -Tags @('modules') -ContinueOnError -SkipOnDryRun -Action {
    $repo = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
    if (-not $repo) {
        throw "PSGallery repository not registered."
    }
    if ($repo.InstallationPolicy -eq 'Trusted') {
        Write-Log -Level DEBUG -Message "  PSGallery already Trusted (skip)"
        return
    }
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    Write-Log -Level DEBUG -Message "  PSGallery -> Trusted (avoids interactive confirm on Install-Module)"
}

Invoke-Step -Name "PS modules: install profile dependencies" -Tags @('modules') -ContinueOnError -SkipOnDryRun -Action {
    $required = @('z', 'Terminal-Icons')
    foreach ($name in $required) {
        if (Get-Module -ListAvailable -Name $name) {
            Write-Log -Level DEBUG -Message "  $name already installed (skip)"
            continue
        }
        Install-Module -Name $name -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        Write-Log -Level DEBUG -Message "  installed: $name"
    }
}
