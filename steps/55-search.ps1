# =============================================================================
# 55 — Disable Windows Search service
#
# Tags: search
#
# Windows Search indexes file content + metadata for:
#   - Start menu file search (the "Start, type filename" workflow)
#   - File Explorer's right-side search bar
#   - Outlook content (full-text email search)
#   - Cortana / search highlights (already neutered by tweaks.reg)
#
# Disabling reclaims CPU/IO at idle — SearchIndexer.exe is a persistent
# background workload. Pre-requisites for living without it:
#
#   - A real file-search alternative (Everything from voidtools is in
#     apps.common.json; uses NTFS MFT directly, doesn't touch the index).
#   - Acceptance that Outlook content search will fall back to a slow
#     per-message scan. App launch via Start still works (apps are in
#     registry, not the index).
#
# This step is OPTIONAL: it's not in the 'core' tag, so it doesn't run by
# default unless 'search' is in your -Steps list, OR you pass no -Steps at
# all (full bootstrap runs every step regardless of tag).
#
# Standalone:
#   Import-Module .\lib\WinSetup; Initialize-Logging; . .\steps\55-search.ps1
# =============================================================================

Invoke-Step -Name "Disable Windows Search service" -Tags @('search') -ContinueOnError -SkipOnDryRun -Action {
    $svc = Get-Service -Name 'WSearch' -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Log -Level DEBUG -Message "  Windows Search service (WSearch) not present — skipping"
        return
    }

    if ($svc.StartType -eq 'Disabled' -and $svc.Status -eq 'Stopped') {
        Write-Log -Level DEBUG -Message "  Already disabled and stopped — no-op"
        return
    }

    if ($svc.StartType -ne 'Disabled') {
        Set-Service -Name 'WSearch' -StartupType Disabled
        Write-Log -Level DEBUG -Message "  Startup type: $($svc.StartType) -> Disabled"
    }

    if ($svc.Status -ne 'Stopped') {
        try {
            Stop-Service -Name 'WSearch' -Force -ErrorAction Stop
            Write-Log -Level DEBUG -Message "  Stopped service"
        } catch {
            Write-Log -Level WARN -Message "  Could not stop service immediately: $($_.Exception.Message)"
            Write-Log -Level WARN -Message "  It will not start on next reboot (StartType=Disabled)."
        }
    }
}
