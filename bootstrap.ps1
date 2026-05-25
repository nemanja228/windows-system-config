#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Post-install automation for Windows 11. Idempotent. Safe to run repeatedly.

.DESCRIPTION
    Each step is tagged. Pass -Steps to run only matching steps, or use one of
    the preset switches. With no flags, all steps run (the original behaviour).

    Tags in use:
        core      — settings most users want every run (debloat, power, defender)
        debloat   — Win11Debloat, OOSU10, tweaks.reg
        privacy   — OOSU10, tweaks.reg (subset of debloat with privacy focus)
        config    — tweaks.reg, .wslconfig (writes config files)
        apps      — winget source update + import
        power     — power plan + USB selective suspend
        defender  — Defender exclusions
        features  — Hyper-V, WSL, VMP, Sandbox feature enables
        wsl       — WSL update, install, .wslconfig
        restore   — system restore point
        checklist — generate TODO file on Desktop

    Pre-flight checks (admin, build version, network, execution policy) have NO
    tags and always run.

.PARAMETER Steps
    Tag list. Steps with matching tags run; others are filtered out.
    Example: -Steps debloat,apps  runs Win11Debloat, OOSU10, tweaks.reg, winget.

.PARAMETER PostUpdate
    Preset for "after a Windows feature update flipped my settings back."
    Equivalent to: -Steps debloat,privacy,features,power,defender

.PARAMETER AppsOnly
    Preset for "just install / update my apps." Equivalent to: -Steps apps

.PARAMETER Verify
    Preset for "show me what would change without changing anything."
    Equivalent to: -DryRun

.PARAMETER DryRun
    Skip destructive actions but log what they would do.

.PARAMETER ForceWslConfig
    Overwrite an existing .wslconfig (with backup). Default behaviour is to
    leave an existing .wslconfig alone — change the script's here-string if you
    want a different canonical config and re-run with this switch.

.EXAMPLE
    .\bootstrap.ps1
    # Run everything (initial install)

.EXAMPLE
    .\bootstrap.ps1 -PostUpdate
    # After Windows feature update: re-flatten settings, re-verify features

.EXAMPLE
    .\bootstrap.ps1 -AppsOnly
    # Just sync apps to apps.json

.EXAMPLE
    .\bootstrap.ps1 -Steps debloat
    # Re-apply debloat tools only

.EXAMPLE
    .\bootstrap.ps1 -Verify
    # Dry-run: show what would happen without touching the system
#>

[CmdletBinding()]
param(
    [string[]]$Steps,
    [switch]$PostUpdate,
    [switch]$AppsOnly,
    [switch]$Verify,
    [switch]$DryRun,
    [switch]$ForceWslConfig
)

# =============================================================================
# Resolve script directory
# =============================================================================

$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $ScriptDir) { $ScriptDir = Get-Location }

# =============================================================================
# Load logging library
# =============================================================================

$libPath = Join-Path $ScriptDir 'lib\Logging.ps1'
if (-not (Test-Path $libPath)) {
    Write-Error "Cannot find $libPath. Make sure the 'lib' folder is alongside this script."
    exit 1
}
. $libPath

# =============================================================================
# Resolve preset switches -> $Steps list
# =============================================================================

# Presets are mutually exclusive with explicit -Steps; explicit wins.
if (-not $Steps -or $Steps.Count -eq 0) {
    if     ($PostUpdate) { $Steps = @('debloat','privacy','features','power','defender') }
    elseif ($AppsOnly)   { $Steps = @('apps') }
}

# -Verify is just -DryRun with a friendlier flag
if ($Verify) { $DryRun = $true }

# =============================================================================
# Initialize logging
# =============================================================================

$init = Initialize-Logging
Set-LoggingFilter -Steps $Steps -DryRun:$DryRun.IsPresent

# Separate per-tool log files
$Script:WingetLog   = Join-Path $init.LogDir "winget-$($init.Stamp).log"
$Script:OosuLog     = Join-Path $init.LogDir "oosu-$($init.Stamp).log"
$Script:DebloatLog  = Join-Path $init.LogDir "win11debloat-$($init.Stamp).log"

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

if ($DryRun)         { Write-Log -Level WARN -Message "MODE:    DRY-RUN — destructive steps will be skipped" }
if ($ForceWslConfig) { Write-Log -Level WARN -Message "FLAG:    -ForceWslConfig — existing .wslconfig will be overwritten (with backup)" }

Write-Log -Level STEP -Message "==============================================="

# =============================================================================
# Pre-flight (no tags — always runs)
# =============================================================================

Invoke-Step -Name "Pre-flight: admin check" -Action {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Not running as Administrator."
    }
    Write-Log -Level DEBUG -Message "  Running as Administrator: OK"
}

Invoke-Step -Name "Pre-flight: Windows build" -ContinueOnError -Action {
    $build = [System.Environment]::OSVersion.Version.Build
    $caption = (Get-CimInstance Win32_OperatingSystem).Caption
    Write-Log -Level DEBUG -Message "  $caption (build $build)"
    if ($build -lt 26100) {
        Write-Log -Level WARN -Message "  Build older than 24H2 (26100). Some features won't apply."
    }
}

Invoke-Step -Name "Pre-flight: network connectivity" -ContinueOnError -Action {
    $reachable = Test-Connection -ComputerName 'github.com' -Count 1 -Quiet -ErrorAction SilentlyContinue
    if (-not $reachable) {
        $reachable = Test-Connection -ComputerName '1.1.1.1' -Count 1 -Quiet -ErrorAction SilentlyContinue
    }
    if (-not $reachable) {
        throw "No network connectivity to github.com or 1.1.1.1"
    }
    Write-Log -Level DEBUG -Message "  Network OK"
}

Invoke-Step -Name "Pre-flight: set execution policy (process scope)" -Action {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
    Write-Log -Level DEBUG -Message "  Policy: Bypass (process)"
}

# =============================================================================
# Restore point
# =============================================================================

Invoke-Step -Name "Create system restore point" -Tags @('restore') -ContinueOnError -SkipOnDryRun -Action {
    Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
    $srKey = 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    if (-not (Test-Path $srKey)) { New-Item -Path $srKey -Force | Out-Null }
    New-ItemProperty -Path $srKey -Name 'SystemRestorePointCreationFrequency' -Value 0 -PropertyType DWord -Force | Out-Null
    Checkpoint-Computer -Description "win-setup bootstrap $($init.Stamp)" -RestorePointType 'MODIFY_SETTINGS'
    Write-Log -Level DEBUG -Message "  Restore point created"
}

# =============================================================================
# Debloat: Win11Debloat
# =============================================================================

Invoke-Step -Name "Win11Debloat (apps + telemetry + UI tweaks)" -Tags @('core','debloat') -ContinueOnError -SkipOnDryRun -Action {
    $customList = Join-Path $ScriptDir 'CustomAppsList.txt'
    if (Test-Path $customList) {
        Write-Log -Level INFO -Message "  Found custom apps list: $customList"
        $cfgDir = Join-Path $env:TEMP 'Win11Debloat\Config'
        if (-not (Test-Path $cfgDir)) { New-Item -Path $cfgDir -ItemType Directory -Force | Out-Null }
        Copy-Item $customList (Join-Path $cfgDir 'CustomAppsList.txt') -Force
        Write-Log -Level DEBUG -Message "  Copied to $cfgDir\CustomAppsList.txt"
    }

    Start-Transcript -Path $Script:DebloatLog -Append -ErrorAction SilentlyContinue | Out-Null
    try {
        & ([scriptblock]::Create((Invoke-RestMethod -Uri "https://debloat.raphi.re/"))) -RunDefaults -Silent
    } finally {
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
    }
    Write-Log -Level DEBUG -Message "  Win11Debloat transcript: $Script:DebloatLog"
}

# =============================================================================
# Debloat: O&O ShutUp10++
# =============================================================================

Invoke-Step -Name "O&O ShutUp10++ (apply saved privacy config)" -Tags @('core','debloat','privacy') -ContinueOnError -SkipOnDryRun -Action {
    $cfgPath = Join-Path $ScriptDir 'ooshutup10.cfg'
    if (-not (Test-Path $cfgPath)) {
        Write-Log -Level WARN -Message "  ooshutup10.cfg not found in $ScriptDir — skipping."
        Write-Log -Level WARN -Message "  Generate one: download OOSU10.exe interactively, configure, File > Export."
        return
    }
    $oosuExe = Join-Path $env:TEMP 'OOSU10.exe'
    Write-Log -Level DEBUG -Message "  Downloading OOSU10.exe"
    Invoke-WebRequest -Uri 'https://dl5.oo-software.com/files/ooshutup10/OOSU10.exe' -OutFile $oosuExe -UseBasicParsing

    Write-Log -Level DEBUG -Message "  Applying config: $cfgPath"
    $procArgs = @("`"$cfgPath`"", '/quiet')
    $p = Start-Process -FilePath $oosuExe -ArgumentList $procArgs -Wait -PassThru `
            -RedirectStandardOutput $Script:OosuLog -RedirectStandardError "$Script:OosuLog.err" -NoNewWindow
    if ($p.ExitCode -ne 0) {
        throw "OOSU10 exited with code $($p.ExitCode). See $Script:OosuLog"
    }
    Write-Log -Level DEBUG -Message "  OOSU10 exit code: 0"
}

# =============================================================================
# Registry tweaks
# =============================================================================

Invoke-Step -Name "Apply registry tweaks (tweaks.reg)" -Tags @('core','debloat','privacy','config') -ContinueOnError -SkipOnDryRun -Action {
    $reg = Join-Path $ScriptDir 'tweaks.reg'
    if (-not (Test-Path $reg)) {
        Write-Log -Level WARN -Message "  tweaks.reg not found in $ScriptDir — skipping."
        return
    }

    # Per-value import. `reg import` of the whole file only emits a generic
    # "Not all data was successfully written" on partial failure — useless for
    # triage. Splitting into one-value temp .reg files surfaces the exact
    # key+value that fails in both the bootstrap log and reg-import-<stamp>.log.

    $regLog = Join-Path $init.LogDir "reg-import-$($init.Stamp).log"
    Set-Content -Path $regLog -Encoding UTF8 -Value @"
Per-value reg import for $reg
Start: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

"@

    $content  = Get-Content -Path $reg -Raw
    $splitIdx = $content.IndexOf("`n[")
    if ($splitIdx -lt 0) {
        throw "No [HKEY_*] sections found in $reg"
    }
    $header = $content.Substring(0, $splitIdx + 1).TrimEnd()
    $rest   = $content.Substring($splitIdx + 1)
    $blocks = $rest -split '(?m)(?=^\[)'

    $okCount = 0
    $failed  = New-Object System.Collections.Generic.List[pscustomobject]

    foreach ($block in $blocks) {
        if ([string]::IsNullOrWhiteSpace($block)) { continue }
        # Join backslash-continuation lines so multi-line binary values stay intact
        $joined = $block -replace '\\\s*\r?\n\s*', ''
        $lines  = $joined -split "`r?`n"
        $keyHeader = $lines[0].Trim()
        if (-not $keyHeader.StartsWith('[')) { continue }

        foreach ($line in $lines[1..($lines.Length - 1)]) {
            $t = $line.Trim()
            if ([string]::IsNullOrWhiteSpace($t)) { continue }
            if ($t.StartsWith(';'))                 { continue }
            if ($t -notmatch '^("[^"]*"|@)\s*=')    { continue }

            $regBody = "$header`r`n`r`n$keyHeader`r`n$t`r`n"
            $tmp = Join-Path $env:TEMP ("regprobe-{0}.reg" -f [guid]::NewGuid())
            Set-Content -LiteralPath $tmp -Value $regBody -Encoding ASCII
            $out  = & reg.exe import $tmp 2>&1
            $code = $LASTEXITCODE
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue

            $valueName = if ($t.StartsWith('@')) { '(Default)' } else { ($t -split '=', 2)[0].Trim('"') }
            $keyPath   = $keyHeader.Trim('[', ']')

            if ($code -eq 0) {
                $okCount++
                Add-Content -Path $regLog -Encoding UTF8 -Value ("[OK  ] {0}\{1}" -f $keyPath, $valueName)
            } else {
                $failed.Add([pscustomobject]@{
                    Key      = $keyPath
                    Value    = $valueName
                    Line     = $t
                    ExitCode = $code
                    Output   = ($out -join ' | ')
                })
                Add-Content -Path $regLog -Encoding UTF8 -Value ("[FAIL] {0}\{1}" -f $keyPath, $valueName)
                Add-Content -Path $regLog -Encoding UTF8 -Value ("       line: $t")
                Add-Content -Path $regLog -Encoding UTF8 -Value ("       exit: $code")
                Add-Content -Path $regLog -Encoding UTF8 -Value ("       out : $($out -join ' | ')")
            }
        }
    }

    Add-Content -Path $regLog -Encoding UTF8 -Value ("`r`nSummary: {0} OK, {1} FAILED" -f $okCount, $failed.Count)

    if ($failed.Count -gt 0) {
        Write-Log -Level WARN -Message "  $($failed.Count) of $($okCount + $failed.Count) registry values failed to import:"
        foreach ($f in $failed) {
            Write-Log -Level WARN -Message ("    ! {0}\{1}  (exit {2}): {3}" -f $f.Key, $f.Value, $f.ExitCode, $f.Output)
        }
        Write-Log -Level WARN -Message "  Detailed log: $regLog"
        if ($okCount -eq 0) {
            throw "All $($failed.Count) registry values failed to import. See $regLog"
        }
    } else {
        Write-Log -Level DEBUG -Message "  All $okCount values imported OK"
    }
}

# =============================================================================
# Time zone (matches Serbia/CET region set in autounattend; reinforce each run)
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

# =============================================================================
# Taskbar auto-hide
# =============================================================================
# StuckRects3\Settings is REG_BINARY — can't be partially written via .reg
# without clobbering position/size bytes. Flip only bit 0 of byte 8:
#   0x02 = visible, 0x03 = auto-hidden.

Invoke-Step -Name "Taskbar: enable auto-hide" -Tags @('core','config') -ContinueOnError -SkipOnDryRun -Action {
    $path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3'
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

# =============================================================================
# Apps via winget
# =============================================================================

Invoke-Step -Name "winget: update sources" -Tags @('apps') -ContinueOnError -SkipOnDryRun -Action {
    winget source update
}

Invoke-Step -Name "winget: import apps.json" -Tags @('apps') -ContinueOnError -SkipOnDryRun -Action {
    $apps = Join-Path $ScriptDir 'apps.json'
    if (-not (Test-Path $apps)) {
        throw "apps.json not found in $ScriptDir"
    }
    Write-Log -Level DEBUG -Message "  Importing $apps  (output -> $Script:WingetLog)"
    & winget import --import-file $apps `
        --accept-package-agreements --accept-source-agreements `
        --ignore-unavailable 2>&1 | Tee-Object -FilePath $Script:WingetLog
}

# =============================================================================
# Power plan
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

# =============================================================================
# Defender exclusions
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

# =============================================================================
# Optional Windows features
# =============================================================================

Invoke-Step -Name "Windows features: Hyper-V, WSL, VMP, Sandbox" -Tags @('features') -ContinueOnError -SkipOnDryRun -Action {
    $features = @(
        'Microsoft-Hyper-V-All',
        'VirtualMachinePlatform',
        'Microsoft-Windows-Subsystem-Linux',
        'Containers-DisposableClientVM'
    )
    foreach ($f in $features) {
        try {
            $state = (Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction Stop).State
            if ($state -eq 'Enabled') {
                Write-Log -Level DEBUG -Message "  = $f (already enabled)"
            } else {
                Enable-WindowsOptionalFeature -Online -FeatureName $f -All -NoRestart -ErrorAction Stop | Out-Null
                Write-Log -Level DEBUG -Message "  + $f (enabled)"
            }
        } catch {
            Write-Log -Level WARN -Message "  ! $f failed: $($_.Exception.Message)"
        }
    }
}

# =============================================================================
# WSL2
# =============================================================================

Invoke-Step -Name "WSL: update kernel" -Tags @('wsl') -ContinueOnError -SkipOnDryRun -Action {
    wsl --update
}

Invoke-Step -Name "WSL: install Ubuntu (if missing)" -Tags @('wsl') -ContinueOnError -SkipOnDryRun -Action {
    $listed = (wsl --list --quiet 2>$null) -join "`n"
    $listed = $listed -replace "`0", ''
    if ($listed -match 'Ubuntu') {
        Write-Log -Level DEBUG -Message "  Ubuntu distro already registered — not touching it"
    } else {
        wsl --install -d Ubuntu --no-launch
        Write-Log -Level DEBUG -Message "  Ubuntu install initiated (finishes on first launch)"
    }
}

Invoke-Step -Name "WSL: write .wslconfig" -Tags @('wsl','config') -SkipOnDryRun -Action {
    $wslConfig = @'
# Managed by win-setup bootstrap.ps1
[wsl2]
memory=16GB
processors=8
swap=4GB
localhostForwarding=true
nestedVirtualization=true

[experimental]
autoMemoryReclaim=gradual
sparseVhd=true
'@
    $path = Join-Path $env:USERPROFILE '.wslconfig'

    if (-not (Test-Path $path)) {
        Set-Content -Path $path -Value $wslConfig -Encoding ASCII -Force
        Write-Log -Level DEBUG -Message "  Wrote $path (file did not exist)"
        return
    }

    $existing = Get-Content $path -Raw -ErrorAction SilentlyContinue
    if ($existing -eq $wslConfig) {
        Write-Log -Level DEBUG -Message "  $path already matches canonical config — no change"
        return
    }

    if (-not $ForceWslConfig) {
        Write-Log -Level WARN -Message "  $path exists and differs from canonical config."
        Write-Log -Level WARN -Message "  Leaving it alone. Pass -ForceWslConfig to overwrite (with backup)."
        return
    }

    $backup = "$path.bak-$($init.Stamp)"
    Copy-Item $path $backup -Force
    Set-Content -Path $path -Value $wslConfig -Encoding ASCII -Force
    Write-Log -Level WARN -Message "  Overwrote $path (backup: $backup)"
}

# =============================================================================
# Manual checklist
# =============================================================================

Invoke-Step -Name "Generate post-install TODO checklist on Desktop" -Tags @('checklist') -Action {
    $todo = @"
================================================================
MANUAL POST-INSTALL CHECKLIST  ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))
================================================================

REBOOT first — Windows features (Hyper-V, WSL, Sandbox) need it.

[ ] Reboot
[ ] Launch Ubuntu once:  wsl -d Ubuntu     # set username + password
[ ] Change local Windows account password (was set to a placeholder by autounattend)
[ ] Sign into MyASUS
       -> Battery Care = Balanced (80%)
       -> Fan Mode = Standard
       -> Function Key Lock = F1-F12 default
[ ] Audient EVO 4:
       -> Download driver: https://audient.com/products/audio-interfaces/evo-4/downloads/
       -> Plug interface DIRECTLY into the laptop, not through the HP G4 dock
       -> Set as default Windows audio device when connected
       -> In DAW: choose 'Audient EVO ASIO', not WASAPI / ASIO4ALL
[ ] BIOS:
       -> Check current vs latest:  https://www.asus.com/laptops/for-home/zenbook/asus-zenbook-s-16-um5606/helpdesk_bios?model2Name=UM5606WA
       -> Confirm SVM (virtualisation) = Enabled
       -> Confirm Secure Boot = Enabled
       -> Confirm fTPM = Enabled
[ ] Office: activate via your MS account in Word > File > Account
[ ] Obsidian: sign into Sync (or set up Syncthing for your vault)
[ ] Git:  git config --global user.name "Your Name"
          git config --global user.email "you@example.com"
[ ] Visual Studio: install workloads (.NET desktop, ASP.NET, Azure dev)
[ ] LatencyMon: run 15 min idle, audit any DPC outliers
[ ] OLED preservation:
       -> Settings > Personalization > Colors = Dark
       -> Taskbar auto-hide is set by bootstrap.ps1 automatically
       -> MyASUS > Device settings > enable Pixel Refresh / Pixel Shift
       -> Wallpaper slideshow every 30 min

================================================================
Bootstrap log:  $($init.LogFile)
Full log dir:   $($init.LogDir)
================================================================
"@
    $todoPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'TODO-post-install.txt'
    Set-Content -Path $todoPath -Value $todo -Encoding UTF8 -Force
    Write-Log -Level INFO -Message "  Wrote $todoPath"
}

# =============================================================================
# Wrap up
# =============================================================================

Show-Summary

$failed = ($script:Summary | Where-Object { -not $_.Success }).Count
Write-Log -Level INFO -Message ""
if ($failed -eq 0) {
    Write-Log -Level SUCCESS -Message "All steps OK. Reboot recommended."
    exit 0
} else {
    Write-Log -Level WARN -Message "$failed step(s) failed. Review the logs above."
    exit 1
}
