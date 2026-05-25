# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Post-install automation for Windows 11 on an ASUS Zenbook S16 UM5606WA (Ryzen AI 9 HX 370, Radeon 890M, OLED). The whole thing is designed to be **idempotent**: re-running after a Windows feature update reverts whatever Microsoft silently re-enabled (Copilot, telemetry, Widgets, web search, etc.). A `-PostUpdate` run is ~60s.

Use cases the design is tuned for: .NET / WSL dev work, music production with an Audient EVO 4, OLED preservation, minimum Microsoft noise, Serbia/CET region with en-US UI. `setup-guide.md` (at repo root) explains the *why* behind every choice.

## ⚠️ Known broken state (reorganization in progress)

The repo is mid-reorg from a flat root layout to `src/<area>/` subfolders. `bootstrap.ps1` has **not yet been updated** to match the new paths. These references will fail until fixed:

| `bootstrap.ps1` line | Looks for | Actually at | Effect if not fixed |
|---|---|---|---|
| 94 | `lib\Logging.ps1` | `Logging.ps1` (root) | Hard exit — bootstrap can't start |
| 205 | `CustomAppsList.txt` (root) | `src/debloat/CustomAppsList.txt` | Win11Debloat skips custom Appx removals (silent skip) |
| 228 | `ooshutup10.cfg` (root) | `src/shutup/ooshutup10.cfg` | OOSU10 step skips with WARN (no privacy config applied) |

`tweaks.reg` and `apps.json` are still at the root, so those paths still work. **Before running `bootstrap.ps1` again**, either move the files back to root or update the three `Join-Path $ScriptDir '...'` calls.

Also at repo root from recent debug sessions (safe to delete, not part of the repo intent): `reg-err.txt`, `test-reg.ps1`.

## Repo layout

```
windows-system-config/
├── bootstrap.ps1                  # Orchestrator, tag-based step filtering, presets
├── Logging.ps1                    # Dot-sourced library (Initialize-Logging, Invoke-Step, Write-Log, Show-Summary)
│                                  #   NOTE: bootstrap.ps1 currently looks for this at lib\Logging.ps1
├── tweaks.reg                     # Registry tweaks (UI/privacy/regional/perf)
├── apps.json                      # winget package list (schema 2.0)
├── setup-guide.md                 # Long-form reference: why each step exists
├── overview.txt                   # User's running manual checklist of install steps
├── README.md                      # User-facing operating manual
├── src/
│   ├── autounattend/
│   │   ├── autounattend.template.xml     # Schneegans XML + win-setup placeholders
│   │   └── render-autounattend.ps1       # Render the template → autounattend.xml
│   ├── debloat/
│   │   └── CustomAppsList.txt            # Win11Debloat custom Appx removals
│   └── shutup/
│       └── ooshutup10.cfg                # O&O ShutUp10++ exported config
└── additions/
    ├── Setup-Git-GitHub.ps1       # Interactive: install git, write SSH profile, apply gist .gitconfig
    ├── Install-Npp-Plugins.ps1    # Install Notepad++ + curated plugin list
    ├── Test-RegImport.ps1         # Diagnose partial-write failures in any .reg (per-value import)
    └── New Text Document.txt      # User's working notes (TODO scratchpad)
```

## Commands

All PowerShell commands run from the repo root. `bootstrap.ps1` requires an **elevated** PowerShell (`#Requires -RunAsAdministrator`).

```powershell
# Full first-time run
.\bootstrap.ps1

# After a Windows feature update — re-flatten settings, ~60s
.\bootstrap.ps1 -PostUpdate

# Sync apps after editing apps.json
.\bootstrap.ps1 -AppsOnly

# Dry run (nothing changes; every step logs what it would do)
.\bootstrap.ps1 -Verify

# Cherry-pick by tag
.\bootstrap.ps1 -Steps privacy           # OOSU10 + tweaks.reg
.\bootstrap.ps1 -Steps power,defender
.\bootstrap.ps1 -Steps wsl

# Force-overwrite existing .wslconfig (default is to leave it alone)
.\bootstrap.ps1 -ForceWslConfig

# Diagnose a failing reg import (per-value granularity, full reg.exe output per failure)
.\additions\Test-RegImport.ps1

# Render the autounattend template to autounattend.xml
.\src\autounattend\render-autounattend.ps1 -ComputerName ... -Username ... -Ssid ... -CSizeGB 350
```

Standalone helpers (interactive, not invoked by `bootstrap.ps1`):

```powershell
.\additions\Setup-Git-GitHub.ps1 -SshEmail ... -KeyAlias ... -HostAlias ... -GistUrl ... -GitUserName ... -GitUserEmail ...
.\additions\Install-Npp-Plugins.ps1
```

No tests, no build, no linter. Pure config + automation scripts.

## Architecture

### Three-layer install pipeline

1. **`autounattend.xml`** — runs during Windows Setup. Skips OOBE, creates the local account, removes Appx packages, applies baseline telemetry settings, partitions the disk. Generated from `src/autounattend/autounattend.template.xml` via `render-autounattend.ps1` (substitutes `_COMPUTERNAME_`, `_ACCOUNTNAME_`, `_PASSWORD_`, `_SSID_`, `_WPA2PASSWORD_`, `_CSizeMB_`, and the hex of the SSID). Lives on the install USB; the rendered `autounattend.xml` is gitignored.
2. **First-logon script** — embedded into `autounattend.xml` as a "runs on first logon" custom script. Downloads this repo and launches `bootstrap.ps1` elevated. (Currently a manual step; no standalone first-logon `.ps1` file in the repo right now.)
3. **`bootstrap.ps1`** — the workhorse. Idempotent, tag-filtered, re-runnable indefinitely.

### `bootstrap.ps1` internals

Dot-sources `Logging.ps1` for `Initialize-Logging`, `Set-LoggingFilter`, `Invoke-Step`, `Write-Log`, `Show-Summary`. Every action is wrapped in `Invoke-Step -Name <label> -Tags @(...) [-ContinueOnError] [-SkipOnDryRun] -Action { ... }`. The wrapper:

- Filters by tag if `$Steps` is set, marks filtered-out steps as `[--]` in the summary.
- Times each step, captures stdout/stderr/warning/error, forwards to console (color-coded) and to `bootstrap-<stamp>.log`.
- Honors `-SkipOnDryRun` (destructive steps no-op under `-DryRun`/`-Verify`).
- Honors `-ContinueOnError` — without it, a step's `throw` aborts the script after printing the summary.
- Final `Show-Summary` prints a table: `[OK]` / `[~ ]` (dry-run) / `[--]` (filtered) / `[X ]` (failed) with duration + error.

### Pipeline (in execution order)

1. **Pre-flight** (no tag, always runs): admin check, Windows build (warns if < build 26100 / 24H2), network, set process-scope execution policy.
2. **System restore point** (`restore`) — overrides the 1440-min throttle so each run gets a checkpoint.
3. **Win11Debloat** (`core, debloat`) — `iex` from `https://debloat.raphi.re/`, `-RunDefaults -Silent`. `CustomAppsList.txt` is copied to `%TEMP%\Win11Debloat\Config\` first.
4. **O&O ShutUp10++** (`core, debloat, privacy`) — `OOSU10.exe` downloaded fresh to `%TEMP%`, applied with `ooshutup10.cfg` and `/quiet`.
5. **`tweaks.reg`** (`core, debloat, privacy, config`) — **per-value import** (split each `[key]\value` into a temp `.reg`, `reg.exe import` each, log per-value OK/FAIL with the exact reg.exe message). Replaces the previous bulk `reg import` because the bulk import only emits a generic "Not all data was successfully written" on partial failure, which is useless for triage. Detailed log at `reg-import-<stamp>.log`; bootstrap log shows a WARN per failure with key + value + exit code + reg.exe output. The step `throw`s only if ALL values fail.
6. **Time zone** (`core, config`) — sets `Central Europe Standard Time` via `Set-TimeZone`. Checks current first so it's a no-op when already correct.
7. **winget source update + import** (`apps`) — `apps.json` is desired-state; removed-but-still-listed apps will be reinstalled.
8. **Power plan** (`core, power`) — duplicate High Performance scheme (`8c5e7fda-...`) if not present; disable USB selective suspend on AC + DC (DPC latency for EVO 4).
9. **Defender exclusions** (`core, defender`) — `~/source`, `~/projects`, `~/.vscode`, `~/.nuget`, REAPER Media dirs, `C:\ProgramData\Audient`.
10. **Windows optional features** (`features`) — Hyper-V, VMP, WSL, Sandbox. `-NoRestart`.
11. **WSL** (`wsl`) — `wsl --update`, install Ubuntu if absent, write `~/.wslconfig` (16GB / 8 procs / sparseVhd / autoMemoryReclaim=gradual). Preserves existing `.wslconfig` unless `-ForceWslConfig`.
12. **TODO checklist** (`checklist`) — generates `TODO-post-install.txt` on Desktop with manual steps (reboot, BIOS, MyASUS, Audient driver, OLED preservation).

### Presets

| Switch | Expands to |
|---|---|
| `-PostUpdate` | `-Steps debloat,privacy,features,power,defender` |
| `-AppsOnly` | `-Steps apps` |
| `-Verify` | `-DryRun` |

### Logs

`%USERPROFILE%\win-setup-logs\` with shared `<stamp>` suffix: `bootstrap-`, `winget-`, `oosu-`, `win11debloat-`, `reg-import-`. The `reg-import-<stamp>.log` is now line-by-line per value (since the per-value rewrite) — search for `[FAIL]` to find failed entries.

## `tweaks.reg` notes

Source of truth for the listed HKCU/HKLM keys. Where its values conflict with what autounattend's first-logon scripts set on the default user profile (`ShowSuperHidden`, `SearchboxTaskbarMode`), tweaks.reg wins because `bootstrap.ps1` re-runs `reg import` after install and after every feature update.

Sections (in current order):
- File Explorer (extensions/hidden/launch/NavPaneShowAllFolders/recents)
- Search & Start menu (Bing kill, search highlights off, taskbar mode)
- Taskbar (Task View off, Chat off, End Task on)
- Copilot / AI (Copilot off, Recall off, Click to Do off)
- Privacy (advertising ID, tailored experiences, http language opt-out, app launch tracking, inking)
- Notifications / suggestions / ads (full ContentDeliveryManager set + SoftLandingEnabled, lock screen, ScoobeSystemSetting)
- AllowOnlineTips (HKLM Explorer policy — kills Settings home suggestions)
- Storage Sense off
- Edge (no startup boost / no prelaunch / no preload)
- Activity history off
- Optional commented blocks: Mouse acceleration, EnableTransparency
- **Regional pack**: `Control Panel\International` (en-US locale + dd.MM.yyyy + 24-hour + Monday first + en-US numbers + metric), `Geo` (RS/271), `Keyboard Layout\Preload` (1=en-US, 2=Serbian Latin)
- **Consumer features policy** (HKLM CloudContent)
- **Cortana service-level kill** (HKLM Windows Search policy)
- **Feedback prompts** off
- **Dark mode** (AppsUseLightTheme=0, SystemUsesLightTheme=0)
- **Taskbar alignment + seconds in clock**
- **Perf**: StartupDelayInMSec=0, MenuShowDelay=200, AutoEndTasks=1, HungAppTimeout=1000
- Optional commented: NlaSvc EnableActiveProbing=0 (breaks captive portal — leave commented unless on stable wifi only)

Time zone is NOT in `tweaks.reg` (binary struct, painful in `.reg` form); it's handled by the dedicated `Set-TimeZone` step in `bootstrap.ps1`.

### Known TaskbarDa issue

`TaskbarDa` (Widgets button) was removed from `tweaks.reg` because importing it consistently fails on this user's machine — the exact reason is unknown but Win11Debloat is the most likely culprit (it sets the same value earlier in the pipeline, possibly with a different type or under a SID-restricted parent). Widgets are still disabled overall via:
- Win11Debloat's `RemoveWidgets` step at the autounattend stage
- `MicrosoftWindows.Client.WebExperience` + `Microsoft.WidgetsPlatformRuntime` in `CustomAppsList.txt`

If you hit similar per-value failures on other keys in the future, run `.\additions\Test-RegImport.ps1` to identify and decide whether to remove or work around.

## Layered debloat philosophy

Each layer fills gaps the previous one leaves — see `setup-guide.md` §10:

1. **autounattend** (cleanest — strips Appx at image time before first boot)
2. **Win11Debloat** (apps + UI tweaks)
3. **O&O ShutUp10++** (granular privacy toggles via the `.cfg`)
4. **`tweaks.reg`** (everything else)

There's an explicit "do not remove" list in `setup-guide.md` (e.g. `Microsoft.NET.*`, `VCLibs`, `WindowsAppRuntime`, WebView2, Microsoft Store) — dependencies for dev work or modern Windows apps. Stripping them silently breaks things later.

`src/debloat/CustomAppsList.txt` recently grew with: Solitaire, Todos, WebExperience (Widgets host), WidgetsPlatformRuntime, DolbyAccess (KEEP DolbyDigitalPlusDecoderOEM — that's the codec), SecureAssessmentBrowser. ASUS PC Assistant (`B9ECED6F.*`) was NOT added because it's likely the MyASUS package which is required for Battery Care / Fan Mode / Live Update.

## Editing conventions

- **Adding a step**: wrap in `Invoke-Step`. Use `-SkipOnDryRun` for destructive actions, `-ContinueOnError` so one failure doesn't abort. Tag appropriately so it shows under existing presets / `-Steps`. Log details with `Write-Log -Level DEBUG`.
- **Adding apps**: append to `apps.json` (winget schema 2.0). `--ignore-unavailable` is already passed.
- **Adding Appx removals**: one PackageFamilyName per line in `src/debloat/CustomAppsList.txt`. Verify exact names with `Get-AppxPackage -AllUsers | Out-GridView` before committing — OEM names drift.
- **Registry tweaks**: prefer `tweaks.reg` over inline PowerShell so changes survive without `bootstrap.ps1`. Group by section with `;`-prefixed headers. Note `dword:` requires no `0x` prefix. REG_SZ values use plain quotes (`"MenuShowDelay"="200"`).
- **Privacy toggles**: regenerate `src/shutup/ooshutup10.cfg` interactively via `OOSU10.exe`, **File → Export**. Don't hand-edit.

## Things this repo intentionally doesn't do

- BitLocker setup
- BIOS update (manual via MyASUS or ASUS support site)
- MyASUS configuration (Battery Care, Fan Mode — not exposed to PowerShell)
- Audient EVO driver install (download manually from audient.com)
- Office activation (sign in via Word > Account)

All listed in the auto-generated `TODO-post-install.txt` on the Desktop.
