#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Post-install automation for Windows 11. Idempotent. Safe to run repeatedly.

.DESCRIPTION
    Thin dispatcher: imports the WinSetup module, sorts steps/*.ps1 alphabetically,
    dot-sources each in order. Step files are runnable standalone too — useful
    for re-applying just one slice (e.g. after editing tweaks.reg).

    Tag filter:
        core      — settings most users want every run (debloat, power)
        debloat   — Win11Debloat, OOSU10, tweaks.reg
        privacy   — OOSU10, tweaks.reg (subset of debloat)
        config    — tweaks.reg, .wslconfig (writes config files)
        apps      — winget source update + import + post-apps cleanup
        extras    — post-install/<package-id>.ps1 hooks (incl. per-app Defender exclusions)
        power     — power plan, USB suspend, LSPM, timeouts
        features  — Hyper-V, WSL, VMP, Sandbox feature enables
        wsl       — WSL update, install, .wslconfig
        restore   — system restore point

    Pre-flight checks (admin, build, network, exec policy) have NO tags and
    always run.

.PARAMETER Steps
    Tag list. Steps with matching tags run; others are filtered out.
    Example: -Steps debloat,apps  runs Win11Debloat, OOSU10, tweaks.reg, winget.

.PARAMETER Tiers
    Which apps.<tier>.json files to import. Default: all four.
    Example: -Tiers common,dev

.PARAMETER PostUpdate
    Preset for "after a Windows feature update flipped my settings back."
    Equivalent to: -Steps debloat,privacy,features,power

.PARAMETER AppsOnly
    Preset for "just install / update my apps." Equivalent to: -Steps apps,extras

.PARAMETER Verify
    Preset for "show me what would change without changing anything." Same as -DryRun.

.PARAMETER DryRun
    Skip destructive actions but log what they would do.

.PARAMETER ForceWslConfig
    Overwrite an existing .wslconfig (with backup). Default behaviour is to
    leave an existing .wslconfig alone.

.PARAMETER ForceAppExtras
    Re-run every post-install/<package-id>.ps1 hook regardless of whether its
    content-hash sentinel matches.

.EXAMPLE
    .\bootstrap.ps1

.EXAMPLE
    .\bootstrap.ps1 -PostUpdate

.EXAMPLE
    .\bootstrap.ps1 -Tiers common -Verify

.EXAMPLE
    .\bootstrap.ps1 -Steps debloat
#>

[CmdletBinding()]
param(
    [string[]]$Steps,

    [ValidateSet('common','dev','work','personal')]
    [string[]]$Tiers = @('common','dev','work','personal'),

    [switch]$PostUpdate,
    [switch]$AppsOnly,
    [switch]$Verify,
    [switch]$DryRun,
    [switch]$ForceWslConfig,
    [switch]$ForceAppExtras
)

# =============================================================================
# Resolve script directory
# =============================================================================

$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $ScriptDir) { $ScriptDir = Get-Location }

# =============================================================================
# Load WinSetup module
# =============================================================================

$modulePath = Join-Path $ScriptDir 'lib\WinSetup'
if (-not (Test-Path $modulePath)) {
    Write-Error "Cannot find WinSetup module at $modulePath. The 'lib\WinSetup' folder must sit alongside this script."
    exit 1
}
Import-Module $modulePath -Force

# =============================================================================
# Resolve preset switches -> $Steps list
# =============================================================================

if (-not $Steps -or $Steps.Count -eq 0) {
    if     ($PostUpdate) { $Steps = @('debloat','privacy','features','power') }
    elseif ($AppsOnly)   { $Steps = @('apps','extras') }
}

# -Verify is just -DryRun with a friendlier flag
if ($Verify) { $DryRun = $true }

# =============================================================================
# Initialize logging
# =============================================================================

$init = Initialize-Logging
Set-LoggingFilter -Steps $Steps -DryRun:$DryRun.IsPresent

# Expose stamp + dir on the dispatcher's script scope so dot-sourced step files
# can read them via $script:LogStamp / $script:LogDir. (The module's $script:
# scope is private to the module — these mirrors let steps see them too.)
$script:LogStamp = $init.Stamp
$script:LogDir   = $init.LogDir
$script:LogFile  = $init.LogFile

# =============================================================================
# Header
# =============================================================================

Write-Log -Level STEP -Message "==============================================="
Write-Log -Level STEP -Message " Windows 11 Post-Install Bootstrap"
Write-Log -Level STEP -Message "==============================================="
Write-Log -Level INFO -Message "Host:    $env:COMPUTERNAME"
Write-Log -Level INFO -Message "User:    $env:USERNAME"
Write-Log -Level INFO -Message "Start:   $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')"
Write-Log -Level INFO -Message "Script:  $ScriptDir"
Write-Log -Level INFO -Message "Log:     $($init.LogFile)"

if ($Steps -and $Steps.Count -gt 0) {
    Write-Log -Level WARN -Message "Filter:  -Steps $($Steps -join ',')"
} else {
    Write-Log -Level INFO -Message "Filter:  (none — running every step)"
}
Write-Log -Level INFO -Message "Tiers:   $($Tiers -join ',')"

if ($DryRun)         { Write-Log -Level WARN -Message "MODE:    DRY-RUN — destructive steps will be skipped" }
if ($ForceWslConfig) { Write-Log -Level WARN -Message "FLAG:    -ForceWslConfig — existing .wslconfig will be overwritten (with backup)" }
if ($ForceAppExtras) { Write-Log -Level WARN -Message "FLAG:    -ForceAppExtras — all post-install hooks will be re-run" }

Write-Log -Level STEP -Message "==============================================="

# =============================================================================
# Dispatch: dot-source each steps/*.ps1 in sorted order
# =============================================================================

$stepsDir = Join-Path $ScriptDir 'steps'
if (-not (Test-Path $stepsDir)) {
    Write-Error "Cannot find steps folder at $stepsDir"
    exit 1
}

Get-ChildItem -Path $stepsDir -Filter '*.ps1' -File |
    Sort-Object Name |
    ForEach-Object {
        Write-Log -Level DEBUG -Message "  dispatch: $($_.Name)"
        . $_.FullName
    }

# =============================================================================
# Wrap up
# =============================================================================

Show-Summary

$failed = (Get-StepSummary | Where-Object { -not $_.Success }).Count
Write-Log -Level INFO -Message ""
if ($failed -eq 0) {
    Write-Log -Level SUCCESS -Message "All steps OK. Reboot recommended."
    exit 0
} else {
    Write-Log -Level WARN -Message "$failed step(s) failed. Review the logs above."
    exit 1
}
