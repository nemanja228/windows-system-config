<#
.SYNOPSIS
    Snapshot MyASUS / ASUS System Control Interface settings to .reg + markdown.

.DESCRIPTION
    ASUS doesn't ship a structured-text export. ASUS Switch produces opaque
    blobs and demands Dropbox / external disk / WiFi targets. This script
    captures the registry-resident half of MyASUS state — most user-facing
    settings live under HKLM\SOFTWARE\ASUS\ASUS System Control Interface
    \AsusOptimization\, including:

      Battery Health Charging threshold (ChargingRate)
      Fan Mode + QuietFan* variants
      Splendid color mode
      AI Noise Cancellation
      OLED Care (Pixel Refresh + Pixel Shift)
      Function Key Lock
      Touchpad / TrackPoint enable
      Keyboard backlight auto-dim

    ASUS's ASUSOptimization service reads these at startup and pushes them
    to firmware via ACPI / EC calls. Restore on a fresh install with the
    companion Import-MyASUSConfig.ps1.

    Output is THREE files in -OutputDir:

      HKLM-ASUS-Keyboard-Hotkeys.reg
      HKLM-ASUS-ScreenXpert.reg
          Raw reg-export of the two value-rich subkeys.

      myasus-snapshot.md
          Curated allowlist of user-settings with current live values.
          Human-readable, diff-friendly, commit-safe (no SN, no UUID).

      README.md
          Per-snapshot index file with capture date, hostname, and
          restore instructions.

    Won't capture (out of registry scope):
      - USB Power Delivery in S5 (pure BIOS setting)
      - Battery wear stats (CycleCount, BATSOH) — telemetry, not settings

    Won't include (machine-identifying, intentionally excluded):
      - HKLM\SOFTWARE\ASUS\Config (serial number, RandomUUID)
      - AsusSurvey, CRM_OOBE, AsusLiveUpdate (telemetry)
      - AsusSystemAnalysis\MTID, USBID (connected-device logs)

.PARAMETER OutputDir
    Where to write the snapshot. Default: ~/win-setup-snapshots/myasus-<stamp>/.
    Directory is created if needed.

.PARAMETER Force
    Overwrite existing files in -OutputDir without prompting.

.EXAMPLE
    .\Export-MyASUSConfig.ps1
    # Default location under $env:USERPROFILE

.EXAMPLE
    .\Export-MyASUSConfig.ps1 -OutputDir 'D:\data\3_library\machine-snapshots\zenbook-myasus'
    # Curated location on data drive

.EXAMPLE
    .\Export-MyASUSConfig.ps1 -WhatIf
    # Preview without writing
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$OutputDir = (Join-Path $env:USERPROFILE "win-setup-snapshots\myasus-$(Get-Date -Format 'yyyyMMdd-HHmmss')"),
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Sanity-check: is this an ASUS machine with SCI installed?
$RootKey = 'HKLM:\SOFTWARE\ASUS\ASUS System Control Interface\AsusOptimization'
if (-not (Test-Path $RootKey)) {
    Write-Error "Not on an ASUS machine, or ASUS System Control Interface not installed. Expected: $RootKey"
    exit 1
}

# Curated allowlist of user-settings. Mechanically: every value name here is
# a thing a human might want to track / diff / restore. Telemetry counters,
# OOBE timestamps, capability flags, and hardware IDs are intentionally
# omitted from this list (though they remain in the raw .reg dump so the
# full state still round-trips).
$Allowlist = @(
    # Battery / Charging
    [pscustomobject]@{ Group='Battery';  SubKey='ASUS Keyboard Hotkeys'; Name='ChargingRate';           Description='Battery Health Charging threshold (%)' }
    [pscustomobject]@{ Group='Battery';  SubKey='ASUS Keyboard Hotkeys'; Name='ChargingSmart';          Description='Smart Charging mode toggle' }
    [pscustomobject]@{ Group='Battery';  SubKey='ScreenXpert';           Name='BatteryCare';            Description='Battery Care mode (mirror of MyASUS UI selection)' }
    [pscustomobject]@{ Group='Battery';  SubKey='ASUS Keyboard Hotkeys'; Name='LowBatteryAction';       Description='Low-battery action' }
    [pscustomobject]@{ Group='Battery';  SubKey='ASUS Keyboard Hotkeys'; Name='HibernateHelper';        Description='Hibernate helper enabled' }

    # Fan / Performance
    [pscustomobject]@{ Group='Fan';      SubKey='ScreenXpert';           Name='FanMode';                Description='Fan mode (model-dependent: 0=Whisper, 1=Standard, 2=Performance)' }
    [pscustomobject]@{ Group='Fan';      SubKey='ASUS Keyboard Hotkeys'; Name='QuietFan';               Description='Quiet Fan on AC' }
    [pscustomobject]@{ Group='Fan';      SubKey='ASUS Keyboard Hotkeys'; Name='QuietFanDC';             Description='Quiet Fan on battery' }
    [pscustomobject]@{ Group='Fan';      SubKey='ASUS Keyboard Hotkeys'; Name='QuietFanPowerMode';      Description='Quiet Fan power-mode flag' }
    [pscustomobject]@{ Group='Fan';      SubKey='ASUS Keyboard Hotkeys'; Name='DynamicPerformanceThreshold'; Description='Dynamic performance threshold' }

    # Display
    [pscustomobject]@{ Group='Display';  SubKey='ScreenXpert';           Name='Splendid';               Description='Splendid color mode' }
    [pscustomobject]@{ Group='Display';  SubKey='ASUS Keyboard Hotkeys'; Name='OLEDProtect';            Description='OLED Pixel Refresh enabled' }
    [pscustomobject]@{ Group='Display';  SubKey='ASUS Keyboard Hotkeys'; Name='PixelShiftStartup';      Description='OLED Pixel Shift on startup' }
    [pscustomobject]@{ Group='Display';  SubKey='ASUS Keyboard Hotkeys'; Name='OLEDProtectScreensaver'; Description='OLED screensaver delay (seconds, 1800 = 30 min)' }
    [pscustomobject]@{ Group='Display';  SubKey='ASUS Keyboard Hotkeys'; Name='OptimalBrightness';      Description='Content-aware optimal brightness' }
    [pscustomobject]@{ Group='Display';  SubKey='ASUS Keyboard Hotkeys'; Name='AutoRefreshRate';        Description='Auto refresh rate toggle' }
    [pscustomobject]@{ Group='Display';  SubKey='ASUS Keyboard Hotkeys'; Name='MultipleRefreshRate';    Description='Multiple refresh rate enabled' }
    [pscustomobject]@{ Group='Display';  SubKey='ASUS Keyboard Hotkeys'; Name='MaxRefreshRateInternal'; Description='Max refresh rate, internal display (Hz)' }

    # Audio / Mic
    [pscustomobject]@{ Group='Audio';    SubKey='ASUS Keyboard Hotkeys'; Name='AINoiseCanceling';       Description='AI Noise Cancellation' }
    [pscustomobject]@{ Group='Audio';    SubKey='ASUS Keyboard Hotkeys'; Name='SpeakerVolumeBoost';     Description='Speaker volume boost' }
    [pscustomobject]@{ Group='Audio';    SubKey='ASUS Keyboard Hotkeys'; Name='MicrophoneEffectKey';    Description='Hotkey code for microphone effects' }
    [pscustomobject]@{ Group='Audio';    SubKey='ASUS Keyboard Hotkeys'; Name='VoicePrintEnabled';      Description='Voice print recognition' }

    # Keyboard backlight
    [pscustomobject]@{ Group='Keyboard'; SubKey='ASUS Keyboard Hotkeys'; Name='AutoKeybdLight';         Description='Auto keyboard backlight (composite flag)' }
    [pscustomobject]@{ Group='Keyboard'; SubKey='ASUS Keyboard Hotkeys'; Name='AutoKeybdLightEx';       Description='Auto keyboard backlight extended' }
    [pscustomobject]@{ Group='Keyboard'; SubKey='ASUS Keyboard Hotkeys'; Name='AutoKeybdLightSection';  Description='Section-based auto backlight' }
    [pscustomobject]@{ Group='Keyboard'; SubKey='ASUS Keyboard Hotkeys'; Name='AutoLockKeybd';          Description='Auto-lock keyboard' }
    [pscustomobject]@{ Group='Keyboard'; SubKey='ASUS Keyboard Hotkeys'; Name='KeybdLightLevel';        Description='Current keyboard backlight level' }
    [pscustomobject]@{ Group='Keyboard'; SubKey='ASUS Keyboard Hotkeys'; Name='TurnOffKeybdLight';      Description='Backlight off delay on AC (seconds)' }
    [pscustomobject]@{ Group='Keyboard'; SubKey='ASUS Keyboard Hotkeys'; Name='TurnOffKeybdLightDC';    Description='Backlight off delay on battery (seconds)' }
    [pscustomobject]@{ Group='Keyboard'; SubKey='ASUS Keyboard Hotkeys'; Name='TurnOffKeybdLightMode';  Description='Backlight off behavior mode' }
    [pscustomobject]@{ Group='Keyboard'; SubKey='ASUS Keyboard Hotkeys'; Name='NKeyRollover';           Description='N-key rollover' }
    [pscustomobject]@{ Group='Keyboard'; SubKey='ASUS Keyboard Hotkeys'; Name='KeybdBatteryAutoLight';  Description='Auto-dim backlight on battery' }
    [pscustomobject]@{ Group='Keyboard'; SubKey='ASUS Keyboard Hotkeys'; Name='KeybdBatteryThreshold';  Description='Battery percent threshold for auto-dim' }

    # Input
    [pscustomobject]@{ Group='Input';    SubKey='ASUS Keyboard Hotkeys'; Name='FnSwitch';               Description='Function Key Lock (1 = F-keys direct, 0 = media-key direct)' }
    [pscustomobject]@{ Group='Input';    SubKey='ASUS Keyboard Hotkeys'; Name='DeviceTouchpad';         Description='Touchpad enabled / feature flags' }
    [pscustomobject]@{ Group='Input';    SubKey='ASUS Keyboard Hotkeys'; Name='DeviceTrackPoint';       Description='TrackPoint enabled' }
    [pscustomobject]@{ Group='Input';    SubKey='ASUS Keyboard Hotkeys'; Name='PhysicalKey';            Description='Physical click only' }

    # Misc
    [pscustomobject]@{ Group='Misc';     SubKey='ASUS Keyboard Hotkeys'; Name='LidClosePrompt';         Description='Prompt on lid close' }
    [pscustomobject]@{ Group='Misc';     SubKey='ASUS Keyboard Hotkeys'; Name='SmartAntenna';           Description='Smart antenna' }
    [pscustomobject]@{ Group='Misc';     SubKey='ASUS Keyboard Hotkeys'; Name='WiFiRoaming';            Description='WiFi roaming' }
    [pscustomobject]@{ Group='Misc';     SubKey='ASUS Keyboard Hotkeys'; Name='PromptSmart';            Description='Smart prompts master toggle' }
)

# --- Create output dir ----------------------------------------------------

if (Test-Path $OutputDir) {
    if (-not $Force -and (Get-ChildItem $OutputDir -Force -ErrorAction SilentlyContinue)) {
        Write-Error "Output directory '$OutputDir' is not empty. Use -Force to overwrite, or pick a different -OutputDir."
        exit 1
    }
} else {
    if ($PSCmdlet.ShouldProcess($OutputDir, "Create directory")) {
        New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
    }
}

Write-Host "Snapshotting to: $OutputDir" -ForegroundColor Cyan

# --- 1. raw .reg dump of the two value-rich subkeys -----------------------

$KbdRegPath = Join-Path $OutputDir 'HKLM-ASUS-Keyboard-Hotkeys.reg'
$SxRegPath  = Join-Path $OutputDir 'HKLM-ASUS-ScreenXpert.reg'

$kbdKey = 'HKLM\SOFTWARE\ASUS\ASUS System Control Interface\AsusOptimization\ASUS Keyboard Hotkeys'
$sxKey  = 'HKLM\SOFTWARE\ASUS\ASUS System Control Interface\AsusOptimization\ScreenXpert'

foreach ($pair in @(@{Key=$kbdKey; File=$KbdRegPath}, @{Key=$sxKey; File=$SxRegPath})) {
    if ($PSCmdlet.ShouldProcess($pair.File, "Export $($pair.Key)")) {
        & reg.exe export $pair.Key $pair.File /y *>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "reg export of '$($pair.Key)' returned exit $LASTEXITCODE — subkey may be absent on this machine."
        } else {
            Write-Host "  wrote: $($pair.File)" -ForegroundColor DarkGray
        }
    }
}

# --- 2. curated markdown snapshot -----------------------------------------

$MdPath = Join-Path $OutputDir 'myasus-snapshot.md'

$rows = New-Object System.Collections.Generic.List[object]
$missing = New-Object System.Collections.Generic.List[string]

foreach ($entry in $Allowlist) {
    $keyPath = "HKLM:\SOFTWARE\ASUS\ASUS System Control Interface\AsusOptimization\$($entry.SubKey)"
    try {
        $v = (Get-ItemProperty -Path $keyPath -Name $entry.Name -ErrorAction Stop).$($entry.Name)
        $rows.Add([pscustomobject]@{
            Group       = $entry.Group
            SubKey      = $entry.SubKey
            Name        = $entry.Name
            Value       = $v
            Description = $entry.Description
        }) | Out-Null
    } catch {
        $missing.Add("$($entry.SubKey)\$($entry.Name)") | Out-Null
    }
}

$lines = New-Object System.Collections.Generic.List[string]
$null = $lines.Add("# MyASUS snapshot")
$null = $lines.Add("")
$null = $lines.Add("- Captured: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')")
$null = $lines.Add("- Host: $env:COMPUTERNAME")
$null = $lines.Add("- Source: ``HKLM\SOFTWARE\ASUS\ASUS System Control Interface\AsusOptimization\``")
$null = $lines.Add("")
$null = $lines.Add("## Settings (curated allowlist)")

foreach ($group in ($rows.Group | Sort-Object -Unique)) {
    $null = $lines.Add("")
    $null = $lines.Add("### $group")
    $null = $lines.Add("")
    $null = $lines.Add("| Setting | Value | SubKey | Notes |")
    $null = $lines.Add("|---|---|---|---|")
    foreach ($r in $rows | Where-Object Group -EQ $group) {
        $valueDisplay = if ($r.Value -is [byte[]]) { "[binary, $($r.Value.Count) bytes]" } else { "$($r.Value)" }
        $nameMd  = '`' + $r.Name + '`'
        $subMd   = '`' + $r.SubKey + '`'
        $null = $lines.Add("| $nameMd | $valueDisplay | $subMd | $($r.Description) |")
    }
}

if ($missing.Count -gt 0) {
    $null = $lines.Add("")
    $null = $lines.Add("## Allowlisted but not present on this machine")
    $null = $lines.Add("")
    foreach ($m in $missing) { $null = $lines.Add("- " + ('`' + $m + '`')) }
}

$null = $lines.Add("")
$null = $lines.Add("## Not captured here (firmware / BIOS)")
$null = $lines.Add("")
$null = $lines.Add("- **USB Power Delivery in S5** -- pure BIOS setting, not visible to Windows. See machine doc for the manual BIOS step.")
$null = $lines.Add("- **Battery wear / health stats** (``CycleCount``, ``BATSOH``) -- telemetry, not user settings.")
$null = $lines.Add("- **UEFI / EC firmware-stored bits** -- out of registry scope. ASUS service syncs the registry values above to firmware on its own.")
$null = $lines.Add("")

if ($PSCmdlet.ShouldProcess($MdPath, "Write markdown snapshot")) {
    Set-Content -Path $MdPath -Value ($lines -join "`r`n") -Encoding UTF8
    Write-Host "  wrote: $MdPath" -ForegroundColor DarkGray
}

# --- 3. per-snapshot README ------------------------------------------------

$ReadmePath = Join-Path $OutputDir 'README.md'

$readme = @(
    "# MyASUS config snapshot"
    ""
    "- Captured: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')"
    "- Host: $env:COMPUTERNAME"
    ""
    "## Contents"
    ""
    "- ``HKLM-ASUS-Keyboard-Hotkeys.reg`` -- raw ``reg export`` of the AsusOptimization\``ASUS Keyboard Hotkeys`` subkey (battery, fan, OLED, keyboard, input)."
    "- ``HKLM-ASUS-ScreenXpert.reg`` -- raw ``reg export`` of the AsusOptimization\``ScreenXpert`` subkey (FanMode, BatteryCare, Splendid)."
    "- ``myasus-snapshot.md`` -- curated allowlist with current live values. Diff-friendly, commit-safe."
    "- ``README.md`` -- this file."
    ""
    "## Restoring on a fresh install"
    ""
    '```powershell'
    ".\snippets\Import-MyASUSConfig.ps1 -InputDir '$OutputDir'"
    '```'
    ""
    "Requires elevation (HKLM write). After import, the script restarts ASUS services so they re-read the registry and push values to firmware where applicable. A reboot is recommended for full firmware sync of bits like the battery-charge threshold."
    ""
    "## Not captured"
    ""
    "See ``myasus-snapshot.md`` for the firmware / BIOS list (USB PD S5, battery wear stats, EC-firmware bits)."
)

if ($PSCmdlet.ShouldProcess($ReadmePath, "Write snapshot README")) {
    Set-Content -Path $ReadmePath -Value ($readme -join "`r`n") -Encoding UTF8
    Write-Host "  wrote: $ReadmePath" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "Snapshot complete: $OutputDir" -ForegroundColor Green
Write-Host "  $($rows.Count) settings captured, $($missing.Count) allowlisted-but-absent." -ForegroundColor Green
