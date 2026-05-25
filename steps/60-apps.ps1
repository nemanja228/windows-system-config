# =============================================================================
# 60 — Apps: winget source update + tiered import + post-apps tweaks re-import
#
# $Tiers is bootstrap-scope (e.g. 'common','professional','personal'). Bootstrap
# defaults it to all three; user can narrow via -Tiers on the command line.
#
# After a successful import, re-applies tweaks.reg via Import-RegFilePerValue.
# This is what cleans up installer-created context-menu junk (Git Bash, etc.)
# that the initial step-20 pass couldn't catch because the apps weren't
# installed yet.
#
# Tags: apps
# =============================================================================

if (-not $script:LogDir)   { $script:LogDir   = Join-Path $env:TEMP 'win-setup-logs' }
if (-not $script:LogStamp) { $script:LogStamp = Get-Date -Format 'yyyyMMdd-HHmmss' }

$WingetLog = Join-Path $script:LogDir "winget-$($script:LogStamp).log"
$RegLog2   = Join-Path $script:LogDir "reg-import-post-apps-$($script:LogStamp).log"

# Track whether the import actually ran, so the post-apps re-import only fires
# when something was installed (not on dry-run, not when filtered out).
$script:AppsImportRan = $false

Invoke-Step -Name "winget: update sources" -Tags @('apps') -ContinueOnError -SkipOnDryRun -Action {
    winget source update
}

Invoke-Step -Name "winget: import tiered apps lists" -Tags @('apps') -ContinueOnError -SkipOnDryRun -Action {
    $effectiveTiers = if ($Tiers) { $Tiers } else { @('common','professional','personal') }
    Write-Log -Level INFO -Message "  Selected tiers: $($effectiveTiers -join ', ')"
    foreach ($tier in $effectiveTiers) {
        $apps = Get-ResourcePath -Name ("winget/apps.{0}.json" -f $tier)
        if (-not (Test-Path $apps)) {
            Write-Log -Level WARN -Message "  $apps not found — skipping tier '$tier'"
            continue
        }
        Write-Log -Level DEBUG -Message "  Importing tier '$tier': $apps  (output -> $WingetLog)"
        & winget import --import-file $apps `
            --accept-package-agreements --accept-source-agreements `
            --ignore-unavailable 2>&1 | Tee-Object -FilePath $WingetLog -Append
    }
    $script:AppsImportRan = $true
}

# Re-apply tweaks.reg AFTER winget so installer-created context-menu entries
# (Git Bash / Git GUI / Open-with-Notepad) get removed on the same run.
# Cheap: ~1s for the full file, every entry is a no-op except the [-...] deletes.
Invoke-Step -Name "Re-apply tweaks.reg (post-apps cleanup)" -Tags @('apps','config') -ContinueOnError -SkipOnDryRun -Action {
    if (-not $script:AppsImportRan) {
        Write-Log -Level DEBUG -Message "  Apps import did not run this session — skipping cleanup pass"
        return
    }
    $reg = Get-ResourcePath -Name 'registry/tweaks.reg'
    if (-not (Test-Path $reg)) {
        Write-Log -Level WARN -Message "  tweaks.reg not found at $reg — skipping cleanup"
        return
    }
    $result = Import-RegFilePerValue -Path $reg -DetailLog $RegLog2
    Write-Log -Level DEBUG -Message "  Re-apply: $($result.OkCount) OK, $($result.FailCount) failed"
    if ($result.FailCount -gt 0) {
        Write-Log -Level WARN -Message "  Detailed log: $RegLog2"
    }
}
