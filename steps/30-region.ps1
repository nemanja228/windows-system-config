# =============================================================================
# 30 — Region + taskbar reinforcement
#
# Time zone (binary REG struct, painful in .reg form — done here)
# Taskbar auto-hide (StuckRects3 binary blob — only flip bit 0 of byte 8)
# Tags: core, config
# =============================================================================

Invoke-Step -Name "Set time zone to Central Europe Standard Time" -Tags @('core','config') -ContinueOnError -SkipOnDryRun -Action {
    $current = (Get-TimeZone).Id
    if ($current -eq 'Central Europe Standard Time') {
        Write-Log -Level DEBUG -Message "  Time zone already correct: $current"
        return
    }
    Set-TimeZone -Id 'Central Europe Standard Time'
    Write-Log -Level DEBUG -Message "  Time zone: $current -> Central Europe Standard Time"
}

# StuckRects3\Settings is REG_BINARY — can't be partially written via .reg
# without clobbering position/size bytes. Flip only bit 0 of byte 8:
#   0x02 = visible, 0x03 = auto-hidden.
Invoke-Step -Name "Taskbar: enable auto-hide" -Tags @('core','config') -ContinueOnError -SkipOnDryRun -Action {
    $path     = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3'
    $settings = (Get-ItemProperty -Path $path).Settings
    if (($settings[8] -band 0x01) -eq 0x01) {
        Write-Log -Level DEBUG -Message "  Taskbar auto-hide already enabled"
        return
    }
    $settings[8] = $settings[8] -bor 0x01
    Set-ItemProperty -Path $path -Name Settings -Value $settings
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Write-Log -Level DEBUG -Message "  Taskbar auto-hide enabled; Explorer restarted"
}
