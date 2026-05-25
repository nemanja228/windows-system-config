# =============================================================================
# 50 — Defender: exclusions for dev/audio folders
#
# Tags: core, defender
# =============================================================================

Invoke-Step -Name "Defender: add exclusions for dev/audio folders" -Tags @('core','defender') -ContinueOnError -SkipOnDryRun -Action {
    $paths = @(
        (Join-Path $env:USERPROFILE 'source'),
        (Join-Path $env:USERPROFILE 'projects'),
        (Join-Path $env:USERPROFILE '.vscode'),
        (Join-Path $env:USERPROFILE '.nuget'),
        (Join-Path $env:USERPROFILE 'Documents\Reaper Media'),
        (Join-Path $env:USERPROFILE 'Documents\REAPER Media'),
        'C:\ProgramData\Audient'
    )
    foreach ($p in $paths) {
        try {
            Add-MpPreference -ExclusionPath $p -ErrorAction Stop
            Write-Log -Level DEBUG -Message "  + $p"
        } catch {
            Write-Log -Level WARN -Message "  ! could not add ${p}: $($_.Exception.Message)"
        }
    }
}
