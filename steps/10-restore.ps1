# =============================================================================
# 10 — System restore point
#
# Overrides the 1440-min throttle so each bootstrap run gets a checkpoint.
# Tags: restore
# =============================================================================

Invoke-Step -Name "Create system restore point" -Tags @('restore') -ContinueOnError -SkipOnDryRun -Action {
    Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
    $srKey = 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    if (-not (Test-Path $srKey)) { New-Item -Path $srKey -Force | Out-Null }
    New-ItemProperty -Path $srKey -Name 'SystemRestorePointCreationFrequency' -Value 0 -PropertyType DWord -Force | Out-Null
    Checkpoint-Computer -Description "win-setup bootstrap $(Get-Date -Format 'yyyyMMdd-HHmmss')" -RestorePointType 'MODIFY_SETTINGS'
    Write-Log -Level DEBUG -Message "  Restore point created"
}
