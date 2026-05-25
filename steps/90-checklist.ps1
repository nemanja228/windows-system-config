# =============================================================================
# 90 — Generate post-install TODO checklist on Desktop
#
# Tags: checklist
# =============================================================================

if (-not $script:LogFile) { $script:LogFile = '(unset)' }
if (-not $script:LogDir)  { $script:LogDir  = '(unset)' }

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
Bootstrap log:  $script:LogFile
Full log dir:   $script:LogDir
================================================================
"@
    $todoPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'TODO-post-install.txt'
    Set-Content -Path $todoPath -Value $todo -Encoding UTF8 -Force
    Write-Log -Level INFO -Message "  Wrote $todoPath"
}
