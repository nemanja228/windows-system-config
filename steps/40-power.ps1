# =============================================================================
# 40 — Power: High Performance plan + USB selective suspend + LSPM + timeouts
#
# Tags: core, power
# =============================================================================

Invoke-Step -Name "Power: restore High Performance plan" -Tags @('core','power') -ContinueOnError -SkipOnDryRun -Action {
    $list = powercfg /list
    if ($list -match 'High performance' -or $list -match 'Ultimate Performance') {
        Write-Log -Level DEBUG -Message "  High Performance plan already present"
    } else {
        powercfg /duplicatescheme 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
        Write-Log -Level DEBUG -Message "  High Performance plan duplicated"
    }
}

Invoke-Step -Name "Power: disable USB selective suspend (AC+DC)" -Tags @('core','power') -ContinueOnError -SkipOnDryRun -Action {
    powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
    powercfg /setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
    powercfg /setactive SCHEME_CURRENT
    Write-Log -Level DEBUG -Message "  USB selective suspend disabled on active plan"
}

Invoke-Step -Name "Power: disable Link State Power Management on AC" -Tags @('core','power') -ContinueOnError -SkipOnDryRun -Action {
    powercfg /setacvalueindex SCHEME_CURRENT 501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 0
    powercfg /setactive SCHEME_CURRENT
    Write-Log -Level DEBUG -Message "  LSPM AC = Off on active plan"
}

Invoke-Step -Name "Power: display timeout, sleep, lid, hibernate" -Tags @('core','power') -ContinueOnError -SkipOnDryRun -Action {
    # Display off: 10 min AC, 3 min DC
    powercfg /setacvalueindex SCHEME_CURRENT SUB_VIDEO VIDEOIDLE 600
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_VIDEO VIDEOIDLE 180
    # Sleep: 30 min AC, 15 min DC
    powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 1800
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 900
    # Lid close = sleep on both AC and DC (1=sleep, 2=hibernate, 3=shutdown)
    powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 1
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 1
    powercfg /setactive SCHEME_CURRENT
    # Disable hibernate — removes hiberfil.sys, reclaims RAM-sized disk space
    powercfg /hibernate off
    Write-Log -Level DEBUG -Message "  Display/sleep timeouts, lid=sleep, hibernate=off applied"
}
