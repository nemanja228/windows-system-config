function Add-DefenderExclusion {
    <#
    .SYNOPSIS
        Add one or more paths to Defender exclusions, idempotently and with
        structured logging via the WinSetup module.

    .DESCRIPTION
        Wrapper around Add-MpPreference -ExclusionPath. Idempotent because
        Add-MpPreference no-ops a path that is already excluded. Designed to be
        called from post-install hooks (steps/61-app-extras.ps1) so each app's
        exclusion lives next to its other setup work, not in a separate
        centralized step.

    .PARAMETER Path
        One or more paths to exclude. Non-existent paths are added anyway —
        Defender accepts them and they take effect when the directory appears.

    .PARAMETER Source
        Optional label for log output, typically the app/hook name (e.g.
        'vscode', 'dotnet', 'reaper'). Shown in the DEBUG log line so failures
        can be traced back to the calling hook.

    .EXAMPLE
        Add-DefenderExclusion -Path "$env:USERPROFILE\.vscode" -Source 'vscode'

    .EXAMPLE
        Add-DefenderExclusion -Path @(
            "$env:USERPROFILE\Documents\Reaper Media",
            "$env:USERPROFILE\Documents\REAPER Media"
        ) -Source 'reaper'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string[]]$Path,
        [string]$Source = ''
    )
    foreach ($p in $Path) {
        try {
            Add-MpPreference -ExclusionPath $p -ErrorAction Stop
            $label = if ($Source) { "[$Source] $p" } else { $p }
            Write-Log -Level DEBUG -Message "  + Defender exclusion: $label"
        } catch {
            Write-Log -Level WARN -Message "  ! could not add Defender exclusion ${p}: $($_.Exception.Message)"
        }
    }
}
