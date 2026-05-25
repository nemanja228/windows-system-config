# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Post-install automation + personal user-level config for Windows 11. Designed to be **idempotent**: re-running after a Windows feature update reverts whatever Microsoft silently re-enabled (Copilot, telemetry, Widgets, web search, lock-screen suggestions, etc.). A `-PostUpdate` run is ~60s.

Use cases the design is tuned for: .NET / WSL dev work, music production with an external audio interface (the user runs an Audient EVO 4), OLED preservation, minimum Microsoft noise, Serbia/CET region with en-US UI. `docs/setup-guide.md` is the entry into the topical docs that explain the *why* behind every choice.

Generic-by-default: machine-specific quirks (vendor app settings, panel quirks, dock issues) are isolated to `docs/machines/<vendor>-<model>.md` so the repo is fork-friendly.

## Repo layout

```
windows-system-config/
├── README.md                      # Entry point + index + quickstart
├── CLAUDE.md                      # This file
├── .gitattributes, .gitignore
├── bootstrap.ps1                  # Thin orchestrator (imports module, iterates steps/)
│
├── docs/                          # Topical docs — machine-AGNOSTIC by default
│   ├── install-checklist.md       # Procedural walkthrough
│   ├── setup-guide.md             # Overview + index to siblings
│   ├── bios.md, drivers.md, oled.md, audio.md, debloat.md, wsl.md
│   ├── post-update.md, git-github.md, terminal-profile.md, troubleshooting.md
│   └── machines/
│       ├── README.md              # Convention for adding machines
│       └── asus-zenbook-s16-um5606wa.md
│
├── lib/WinSetup/                  # PowerShell module
│   ├── WinSetup.psd1              # Manifest (exports 8 functions)
│   ├── WinSetup.psm1              # Loader (dot-sources Public/*.ps1)
│   ├── Public/                    # One file per exported function
│   │   ├── Initialize-Logging.ps1, Set-LoggingFilter.ps1
│   │   ├── Write-Log.ps1, Invoke-Step.ps1, Show-Summary.ps1
│   │   ├── Get-StepSummary.ps1    # NEW: exposes $script:Summary across module boundary
│   │   ├── Get-ResourcePath.ps1   # NEW: resolves names against the repo's resources/ tree
│   │   └── Import-RegFilePerValue.ps1  # NEW: per-value .reg import w/ structured result
│   └── Private/                   # Placeholder for future internal helpers
│
├── steps/                         # Bootstrap step files — composable, standalone-runnable
│   ├── 00-preflight.ps1           # admin / build / network / exec policy
│   ├── 10-restore.ps1             # system restore point
│   ├── 20-debloat.ps1             # Win11Debloat + OOSU10 + tweaks.reg (per-value)
│   ├── 30-region.ps1              # time zone + taskbar autohide
│   ├── 40-power.ps1               # High Performance plan + USB suspend + LSPM + timeouts
│   ├── 50-defender.ps1            # Defender exclusions for dev/audio dirs
│   ├── 55-search.ps1              # Disable Windows Search service (optional, tag 'search')
│   ├── 60-apps.ps1                # winget source update + tiered import + post-apps tweaks re-import
│   ├── 61-app-extras.ps1          # auto-run post-install/<PackageId>.ps1 hooks
│   ├── 70-features-wsl.ps1        # Windows features + WSL update/install + .wslconfig
│   └── 80-profiles.ps1            # Wraps scripts/Install-Profiles.ps1 (-NoInit), deploys profiles/
│
├── resources/                     # Input data consumed by step scripts
│   ├── autounattend/              # autounattend.xml template + renderer
│   ├── debloat/                   # Win11Debloat CustomAppsList.txt
│   ├── shutup/                    # O&O ShutUp10++ saved cfg
│   ├── registry/                  # tweaks.reg
│   └── winget/                    # apps.{common,professional,personal}.json
│
├── post-install/                  # Per-app hooks (auto-discovered by 61-app-extras)
│   ├── README.md                  # Naming convention + idempotency contract
│   ├── Notepad++.Notepad++.ps1    # Plugin sideload
│   └── Microsoft.VisualStudioCode.ps1  # Extension install
│
├── scripts/                       # Standalone interactive scripts (not in bootstrap)
│   ├── Setup-Git.ps1              # Install git + deploy gitconfig + set identity (idempotent)
│   ├── New-GitHubSshProfile.ps1   # Add a GitHub SSH profile (idempotent, reusable per account)
│   ├── Install-Profiles.ps1       # Deploy profiles/ into OS locations (incl. git w/ identity preservation)
│   ├── Install-ClaudeCode.ps1     # Anthropic installer + PATH add
│   └── Test-RegImport.ps1         # Diagnose per-value reg import failures
│
├── profiles/                      # Personal user-level configs (no personal IDs)
│   ├── README.md
│   ├── git/.gitconfig             # Identity-free; user.name/email set live by Setup-Git, preserved across redeploys
│   ├── powershell/Microsoft.PowerShell_profile.ps1
│   ├── windows-terminal/settings.json   # JSONC, profiles.list intentionally omitted
│   ├── oh-my-posh/winsetup.omp.json
│   ├── autohotkey/WtTransparent.ahk      # AHK v2; toggle window transparency
│   └── fonts/CaskaydiaCoveNerdFontMono-{Regular,Bold,Italic,BoldItalic}.ttf
│
└── snippets/                      # Standalone PowerShell utility scripts
    ├── README.md
    ├── Add-ToPath.ps1, Remove-FromPath.ps1, Get-PathEntries.ps1
```

## Commands

All PowerShell commands run from the repo root. `bootstrap.ps1` has `#Requires -RunAsAdministrator` — it refuses to start in a non-elevated session.

```powershell
# Full first-time run
.\bootstrap.ps1

# After a Windows feature update — re-flatten settings, ~60s
.\bootstrap.ps1 -PostUpdate         # -Steps debloat,privacy,features,power,defender

# Just apps + their post-install hooks
.\bootstrap.ps1 -AppsOnly           # -Steps apps,extras

# Dry run (nothing changes; every step logs what it would do)
.\bootstrap.ps1 -Verify             # = -DryRun

# Cherry-pick by tag
.\bootstrap.ps1 -Steps privacy           # OOSU10 + tweaks.reg
.\bootstrap.ps1 -Steps power,defender
.\bootstrap.ps1 -Steps wsl
.\bootstrap.ps1 -Steps extras            # just the post-install/ hooks

# App tier filter (independent of -Steps)
.\bootstrap.ps1 -Tiers common,professional       # default: all three
.\bootstrap.ps1 -Tiers common -AppsOnly

# Force flags
.\bootstrap.ps1 -ForceWslConfig          # overwrite existing .wslconfig (with backup)
.\bootstrap.ps1 -ForceAppExtras          # re-run every post-install hook regardless of sentinel

# Diagnose a failing reg import (per-value granularity, full reg.exe output per failure)
.\scripts\Test-RegImport.ps1

# Render the autounattend template to autounattend.xml
.\resources\autounattend\render-autounattend.ps1 -ComputerName ... -Username ... -Ssid ... -CSizeGB 350
```

Standalone scripts (interactive, not invoked by `bootstrap.ps1`):

```powershell
# Git: install + apply repo .gitconfig + set identity (idempotent, identity preserved)
.\scripts\Setup-Git.ps1                                                   # auto-prompts only if identity missing
.\scripts\Setup-Git.ps1 -GitUserName 'X' -GitUserEmail 'y@example.com'    # set explicitly

# New SSH profile (reusable per GitHub account; idempotent)
.\scripts\New-GitHubSshProfile.ps1 -Email 'me@example.com'
.\scripts\New-GitHubSshProfile.ps1 -Email 'me@work.com' -KeyAlias 'id_ed25519_work' -HostAlias 'github.com-work'

# Deploy profiles into OS locations (copy by default; -Symlink needs elevation or Dev Mode)
.\scripts\Install-Profiles.ps1
.\scripts\Install-Profiles.ps1 -Only git,pwsh
.\scripts\Install-Profiles.ps1 -WhatIf

# Claude Code (default: Anthropic's PS installer; -Method Winget for the alternative)
.\scripts\Install-ClaudeCode.ps1
.\scripts\Install-ClaudeCode.ps1 -Method Winget

# PATH cmdlets (snippets — fully standalone, no module needed)
.\snippets\Add-ToPath.ps1 -Path 'C:\Tools\bin'
.\snippets\Add-ToPath.ps1 -Path 'C:\Tools\bin' -Scope Machine
.\snippets\Remove-FromPath.ps1 -Path 'C:\OldTool'
.\snippets\Get-PathEntries.ps1                  # all scopes, color-coded
```

No tests, no build, no linter. Pure config + automation scripts.

## Architecture

### Three-layer install pipeline

1. **`autounattend.xml`** — runs during Windows Setup. Skips OOBE, creates the local account, removes Appx packages, applies baseline telemetry settings, partitions the disk. Generated from `resources/autounattend/autounattend.template.xml` via `render-autounattend.ps1` (substitutes computer name, username, password, Wi-Fi SSID/password, install drive size, plus the hex form of the SSID). Lives on the install USB; the rendered `autounattend.xml` is gitignored.
2. **First-logon script** — embedded in `autounattend.xml` as a "runs on first logon" custom script. Downloads this repo and launches `bootstrap.ps1` elevated. (Currently a manual step; no standalone first-logon `.ps1` file in the repo right now.)
3. **`bootstrap.ps1`** — the workhorse. Idempotent, tag-filtered, re-runnable indefinitely.

### `bootstrap.ps1` internals

`bootstrap.ps1` is a ~150-line dispatcher: imports the `WinSetup` module, expands preset switches (`-PostUpdate`, `-AppsOnly`, `-Verify`) into a `-Steps` filter, initializes logging, mirrors `$init.Stamp`/`$init.LogDir` onto its own `$script:` scope so dot-sourced step files can read them, then iterates `steps/*.ps1` in alphabetical order, dot-sourcing each.

Every action is wrapped in `Invoke-Step -Name <label> -Tags @(...) [-ContinueOnError] [-SkipOnDryRun] -Action { ... }`. The wrapper:

- Filters by tag if `$Steps` is set, marks filtered-out steps as `[--]` in the summary.
- Times each step, captures stdout/stderr/warning/error, forwards to console (color-coded) and to `bootstrap-<stamp>.log`.
- Honors `-SkipOnDryRun` (destructive steps no-op under `-DryRun`/`-Verify`).
- Honors `-ContinueOnError` — without it, a step's `throw` aborts the script after printing the summary.
- Final `Show-Summary` prints a table: `[OK]` / `[~ ]` (dry-run) / `[--]` (filtered) / `[X ]` (failed) with duration + error.

Module helpers used by steps:

- **`Get-ResourcePath -Name 'registry/tweaks.reg'`** — resolves a path under `resources/` (or `-Area <other>` for `post-install/`, `profiles/`, etc.) against the repo root, regardless of where the calling script lives.
- **`Import-RegFilePerValue -Path <file> -DetailLog <path>`** — splits a `.reg` into one-value temp files, imports each, returns a structured result `{ OkCount, FailCount, Failed[] }`. Used by step 20 (initial tweaks.reg) AND step 60 (post-apps re-import to clean up installer-created context-menu junk like Git Bash). Also handles `[-HKEY_...]` key-delete entries needed for the Open-with-Notepad / Git Bash / Git GUI removals.
- **`Get-StepSummary`** — returns `$script:Summary` across the module boundary (the module's `$script:` scope is private, so bootstrap and 61-app-extras can't read it directly; this helper does).

### Pipeline (in execution order, by step file)

1. **`00-preflight.ps1`** (no tags, always runs): admin check, Windows build (warns if < build 26100 / 24H2), network, set process-scope execution policy.
2. **`10-restore.ps1`** (`restore`) — system restore point. Overrides the 1440-min throttle so each run gets a checkpoint.
3. **`20-debloat.ps1`** (`core, debloat`):
   - Win11Debloat — `iex` from `https://debloat.raphi.re/`, `-RunDefaults -Silent`. `CustomAppsList.txt` copied to `%TEMP%\Win11Debloat\Config\` first.
   - O&O ShutUp10++ — `OOSU10.exe` downloaded fresh to `%TEMP%`, applied with `ooshutup10.cfg` and `/quiet`. Tagged `core, debloat, privacy`.
   - `tweaks.reg` — per-value import via `Import-RegFilePerValue`. Detailed per-value log at `reg-import-<stamp>.log`; bootstrap log shows a WARN per failure with key + value + exit code + reg.exe output. The step `throw`s only if ALL values fail. Tagged `core, debloat, privacy, config`.
4. **`30-region.ps1`** (`core, config`) — `Central Europe Standard Time` via `Set-TimeZone` (no-op when already correct), taskbar autohide via `StuckRects3` binary blob (flips bit 0 of byte 8 — 0x02 = visible, 0x03 = autohidden; restarts explorer.exe).
5. **`40-power.ps1`** (`core, power`) — duplicate High Performance scheme if not present, disable USB selective suspend on AC+DC (DPC latency for EVO 4), disable Link State Power Management on AC, set display/sleep timeouts + lid=sleep + `powercfg /hibernate off`.
6. **`50-defender.ps1`** (`core, defender`) — exclusions for `~/source`, `~/projects`, `~/.vscode`, `~/.nuget`, REAPER Media dirs, `C:\ProgramData\Audient`.
7. **`55-search.ps1`** (`search`) — disables Windows Search service (sets WSearch StartupType=Disabled + Stop-Service). Idempotent (no-op when already disabled+stopped). Outlook content search breaks; Start file search breaks; Everything replaces them. See `docs/debloat.md` for the full tradeoff write-up.
8. **`60-apps.ps1`** (`apps`) — `winget source update`, then `winget import` for each `apps.<tier>.json` matched by `-Tiers` (default: all three: common, professional, personal). After successful import, **re-applies `tweaks.reg`** via `Import-RegFilePerValue` — cheap (~1s, mostly no-ops) and cleans up installer-created context-menu entries (Git Bash, "Open with Notepad", etc.) that step 20 couldn't catch because the apps weren't installed yet.
9. **`61-app-extras.ps1`** (`apps, extras`) — scans `post-install/*.ps1`. For each, strips `.ps1` to get the package id, checks `winget list --id <id> --exact`, and if installed, compares SHA-256 of the script content against a sentinel at `%LocalAppData%\win-setup\post-install\<id>.hash`. If hash differs (or sentinel missing) runs the script with `Invoke-Step`; else skips with DEBUG. `-ForceAppExtras` clears sentinels first.
10. **`70-features-wsl.ps1`** (`features` / `wsl`) — Hyper-V, VMP, WSL, Sandbox features (`-NoRestart`), `wsl --update`, install Ubuntu if absent, write `~/.wslconfig` (16GB / 8 procs / sparseVhd / autoMemoryReclaim=gradual). Preserves existing `.wslconfig` unless `-ForceWslConfig`.
11. **`80-profiles.ps1`** (`profiles` + per-category sub-tags: `git`, `pwsh`, `omp`, `wt`, `fonts`, `ahk`) — thin wrapper that invokes `scripts/Install-Profiles.ps1 -NoInit`. The inner script's six category-specific Invoke-Step calls land in the bootstrap summary because the module's `$script:Summary` is shared. `Install-Profiles.ps1` is also runnable standalone for ad-hoc redeployment after editing a `profiles/*` file.

The manual-step "what to do after bootstrap finishes" list lives in [`docs/install-checklist.md`](docs/install-checklist.md) § 15 — that's the source of truth for all manual installs (Office, eUprava, vendor apps, Native Instruments, etc.). Earlier versions of the repo generated `TODO-post-install.txt` on the Desktop from a bootstrap step; that step was removed because keeping the manual-step content in two places (Desktop file + docs) drifted, and the doc wins as the canonical home.

### Presets

| Switch | Expands to |
|---|---|
| `-PostUpdate` | `-Steps debloat,privacy,features,power,defender` |
| `-AppsOnly` | `-Steps apps,extras` |
| `-Verify` | `-DryRun` |

### App tiers

Three winget package lists under `resources/winget/`:

- **`apps.common.json`** (22 packages) — everyday tools any of the user's machines should have: PowerShell, Git, gh, OhMyPosh, VS Code, PowerToys, .NET 10 SDK, Docker Desktop, Firefox, Chrome, Notepad++, Obsidian, Everything, Insync, 7zip, Bitwarden CLI, PDF24, AutoHotkey v2, VLC, WizTree, Logitech Options+, UniGetUI.
- **`apps.professional.json`** (7 packages) — work tooling: JetBrains Toolbox, SSMS, .NET 8 SDK (LTS), fnm, pyenv-win, WinMerge, WinSCP.
- **`apps.personal.json`** (4 packages) — taste-driven: LatencyMon, REAPER, TuxGuitar, GeForce Now.

Selected via `-Tiers`. Default: all three. Tier-per-file (not one JSON with tags) because `winget import` consumes whole files.

### Per-app post-install hooks

`post-install/<exact-winget-package-id>.ps1`. Step `61-app-extras` derives the id from the filename, checks `winget list`, hashes the script, and runs if either not-yet-run or the hash changed. Hook scripts must be **internally idempotent** — the hash sentinel is a perf optimization, not a correctness guarantee. Currently shipped: `Notepad++.Notepad++.ps1` (plugin sideload), `Microsoft.VisualStudioCode.ps1` (extension install).

### Logs

`%USERPROFILE%\win-setup-logs\` with shared `<stamp>` suffix:

- `bootstrap-<stamp>.log` — master log
- `winget-<stamp>.log` — raw winget output
- `oosu-<stamp>.log` — OOSU10 stdout
- `win11debloat-<stamp>.log` — Win11Debloat transcript
- `reg-import-<stamp>.log` — step 20 per-value import detail
- `reg-import-post-apps-<stamp>.log` — step 60 re-import detail
- `install-profiles-<stamp>.log` (when `Install-Profiles.ps1` runs)
- `install-claude-<stamp>.log` (when `Install-ClaudeCode.ps1` runs)

Each line is timestamped; per-value reg import logs are line-by-line — search for `[FAIL]` to find failed entries.

## `tweaks.reg` notes

Source of truth for HKCU/HKLM keys not covered by Win11Debloat or O&O ShutUp10++. `bootstrap.ps1` imports it twice per full run: step 20 (initial pass) and step 60 (post-apps cleanup, because Git's installer re-adds shell context-menu entries that step 20 couldn't remove yet).

Sections in current order: File Explorer, Search & Start menu, Taskbar, Copilot/AI, Privacy, Notifications/suggestions/ads, AllowOnlineTips, Storage Sense, Edge (no startup boost/prelaunch/preload), Activity history, optional commented blocks (mouse accel, transparency), Regional pack (en-US locale + dd.MM.yyyy + 24-hour + Monday first + RS Geo + Serbian Latin keyboard), Consumer features policy, Cortana service-level kill, Feedback prompts, Dark mode, Taskbar alignment + seconds in clock, Perf (StartupDelay/MenuShowDelay/AutoEndTasks/HungAppTimeout), Wallpaper slideshow (30-min OLED-safe), commented NlaSvc EnableActiveProbing.

**New entries added in Phase 1**: classic Win10 right-click context menu (HKCU CLSID InprocServer32 empty default), OneDrive autostart disabled (Run-key value deletion + StartupApproved binary), `[-HKLM\…\*\shell\Open with Notepad]` key delete, `[-HKLM\…\Directory\{Background\,}shell\git_{shell,gui}]` four key deletes.

Time zone is NOT in `tweaks.reg` (binary struct, painful in `.reg` form); it's handled by the dedicated `Set-TimeZone` step in `30-region.ps1`.

### Known TaskbarDa issue

`TaskbarDa` (Widgets button) was removed from `tweaks.reg` because importing it consistently fails on this user's machine — the exact reason is unknown but Win11Debloat is the most likely culprit (it sets the same value earlier in the pipeline, possibly with a different type or under a SID-restricted parent). Widgets are still disabled overall via:

- Win11Debloat's `RemoveWidgets` step at the autounattend stage
- `MicrosoftWindows.Client.WebExperience` + `Microsoft.WidgetsPlatformRuntime` in `resources/debloat/CustomAppsList.txt`

If you hit similar per-value failures on other keys in the future, run `.\scripts\Test-RegImport.ps1` to identify and decide whether to remove or work around.

## Layered debloat philosophy

Each layer fills gaps the previous one leaves — see `docs/debloat.md`:

1. **autounattend** (cleanest — strips Appx at image time before first boot)
2. **Win11Debloat** (apps + UI tweaks)
3. **O&O ShutUp10++** (granular privacy toggles via the `.cfg`)
4. **`tweaks.reg`** (everything else, with the post-apps re-import catching installer-added context-menu junk)

There's an explicit "do not remove" list in `docs/debloat.md` (e.g. `Microsoft.NET.*`, `VCLibs`, `WindowsAppRuntime`, WebView2, Microsoft Store) — dependencies for dev work or modern Windows apps. Stripping them silently breaks things later.

## Editing conventions

- **Adding a bootstrap step**: create `steps/NN-name.ps1` (NN sets execution order; gaps left in 10s so new sections slot in cleanly). Wrap actions in `Invoke-Step`. Use `-SkipOnDryRun` for destructive actions, `-ContinueOnError` so one failure doesn't abort. Tag appropriately so it shows under existing presets / `-Steps`. Log details with `Write-Log -Level DEBUG`. The dispatcher picks up new step files automatically — no edit to `bootstrap.ps1` needed.
- **Adding apps**: append to the right `resources/winget/apps.<tier>.json`. winget schema 2.0. `--ignore-unavailable` is already passed by step 60.
- **Adding a per-app hook**: drop `post-install/<exact-winget-package-id>.ps1`. Step 61 finds it on next run, hashes it, runs only when installed + hash changed. Hook must be internally idempotent.
- **Adding Appx removals**: one PackageFamilyName per line in `resources/debloat/CustomAppsList.txt`. Verify exact names with `Get-AppxPackage -AllUsers | Out-GridView` before committing — OEM names drift.
- **Registry tweaks**: prefer `resources/registry/tweaks.reg` over inline PowerShell so changes survive without `bootstrap.ps1`. Group by section with `;`-prefixed headers. Note `dword:` requires no `0x` prefix. REG_SZ values use plain quotes (`"MenuShowDelay"="200"`). Key-delete form `[-HKLM\…]` is supported by `Import-RegFilePerValue`.
- **Privacy toggles**: regenerate `resources/shutup/ooshutup10.cfg` interactively via `OOSU10.exe`, **File → Export**. Don't hand-edit.
- **Adding a module helper**: write `lib/WinSetup/Public/<Verb-Noun>.ps1` with a `function Verb-Noun { ... }` block. Add the name to `FunctionsToExport` in `WinSetup.psd1`. The loader auto-discovers it.
- **Adding a snippet**: drop `snippets/<Verb-Noun>.ps1`. Must be fully standalone (no module dependency) so it can be `irm`'d to any machine. Document in `snippets/README.md`. Use `[CmdletBinding(SupportsShouldProcess)]` if destructive, support `-WhatIf`. Make it idempotent.
- **Adding a profile category** (e.g. a new app's user-level config files): create `profiles/<category>/`, add the deployment block to `scripts/Install-Profiles.ps1` (one `Invoke-Step` per category, copy/symlink with backup), update `profiles/README.md` and `docs/terminal-profile.md`.
- **Adding a machine doc**: copy `docs/machines/asus-zenbook-s16-um5606wa.md` as a template, fill in the machine-specific bits, link from the generic docs where relevant. Avoid leaking machine-specific content into generic docs — `docs/troubleshooting.md` has an example of the pattern.
- **PowerShell file encoding**: save `.ps1` files as **UTF-8 with BOM** when they contain non-ASCII characters (em-dashes in comments are the usual culprit). Without BOM, PS 5.1 reads them as CP1252 and mangles multi-byte chars into parser errors. PS 7 doesn't care, but the repo targets both.

## Things this repo intentionally doesn't do

- BitLocker setup
- BIOS update (manual via vendor app or support site)
- Vendor app configuration (MyASUS Battery Care, Fan Mode, etc. — UI-only, no PowerShell API; see `docs/machines/`)
- Audient EVO driver install (download manually from audient.com)
- Office activation (sign in via Word > Account; install via Office Deployment Tool — see `docs/install-checklist.md` § 15)
- Anything in the manual-install bucket: CoolerMaster MasterPlus+, Guitar Pro 7.5 (winget only has v8), Native Instruments Guitar Rig (via Native Access), Arturia keyboard software, Serbian eUprava tools (Čelik / TrustEdgeID / ePorezi)

All documented in detail in `docs/install-checklist.md` § 15.
