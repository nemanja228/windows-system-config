# Install checklist

End-to-end procedural walkthrough for a fresh Windows 11 install using this repo. Each section is sequential; cross-references to scripts and `bootstrap.ps1` switches are inline.

For the *why* behind each step (debloat philosophy, OLED preservation, BIOS settings, etc.) see [`setup-guide.md`](setup-guide.md) and the topical docs in this folder. Machine-specific quirks live under [`machines/`](machines/).

---

## 1. Pre-install

- [ ] **Update BIOS** to the current version before installing Windows (firmware-validated drivers depend on it). Easiest path: vendor app on the existing OS, or EZ Flash from a FAT32 USB if the vendor has a direct BIOS file.
- [ ] **Download a current Windows 11 ISO** (24H2 or 25H2) from Microsoft. Don't use Rufus's "tweaked install" mode — it injects its own `autounattend.xml` that would override the one in this repo.
- [ ] **Render `autounattend.xml`** from this repo's template — see [`../resources/autounattend/`](../resources/autounattend/). Run `render-autounattend.ps1` interactively or with parameters; it prompts for computer name, local username, password, Wi-Fi SSID and password, and install-drive size.
- [ ] **Put the rendered `autounattend.xml` on the install USB root**, then boot from it.

## 2. Unattended install (handled by `autounattend.xml`)

These choices are encoded in the template; included here so you know what to expect:

- US display language + Serbian Latin secondary keyboard layout
- Serbian region
- Install drive ~350 GB (configurable via `-CSizeGB`)
- Local account, OOBE skipped
- Telemetry baseline denied
- (Wi-Fi driver: install separately after first boot if the USB's network stack didn't pick yours up)

## 3. First boot — updates and drivers (manual)

Driver-update order matters: the vendor app pulls a curated driver pack validated against your firmware, while later AMD/Intel direct-from-vendor updates usually supersede pieces of it.

- [ ] **Pause Windows Update** for ~1 week (Settings → Windows Update) so it doesn't fight you while you install drivers.
- [ ] **Update Microsoft Store** (Store → Library → Get updates).
- [ ] **Install the vendor app** (e.g. MyASUS) and run its Live Update — pulls the validated driver pack: chipset, audio, fingerprint, FN keys, system control interface.
- [ ] **Update BIOS** if not done in step 1.
- [ ] **Update drivers automatically** via the vendor app.
- [ ] **Update chipset / CPU / GPU** drivers directly from AMD or Intel — these are usually newer than what the vendor ships and include scheduler updates (e.g. Zen 5 hybrid topology).
- [ ] **Resume Windows Update** and let it patch the rest. Re-run until "no updates available."

See [`drivers.md`](drivers.md) for the rationale and [`machines/`](machines/) for any device-specific notes (vendor app settings, panel quirks, audio interface notes).

## 4. Activate Windows

- [ ] Sign in or paste a product key (Settings → System → Activation).

## 5. Set up drives

After install drive is provisioned, partition the rest of the disk:

- [ ] **Install drive** — already exists from step 2 (~350 GB).
- [ ] **Dev Drive** — ReFS volume sized for source trees and package caches (e.g. 150 GB). Settings → System → Storage → Disks & volumes → Create Dev Drive. Dev Drive enables ReFS + Performance Mode for Defender.
- [ ] **Data drive** — remaining space, NTFS. Mount as `D:\` (or whatever letter).

## 6. PowerShell execution policy

The autounattend handles this for fresh installs. If running scripts on an existing install: open an elevated PowerShell and run

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

`bootstrap.ps1` re-applies the process-scope policy on every run regardless.

## 7. Firefox (browser-bootstrap, manual)

Install Firefox first so the rest of the auth steps can be done in your real browser, not Edge.

```powershell
winget install --id Mozilla.Firefox -e
```

Then:

- [ ] Set Firefox as default browser (Settings → Apps → Default apps).
- [ ] Sign into Bitwarden web app with your unlock key.
- [ ] Sign into Google with key (via Bitwarden autofill).
- [ ] Sign into Mozilla account → activate sync.
- [ ] Install Bitwarden extension → sign in with key.

## 8. Insync (Google Drive sync, manual)

- [ ] Install Insync.
- [ ] Turn off all base-folder syncs (Documents, Desktop, etc.).
- [ ] Manually set up `_data` folder sync to `D:\data` (or wherever the data drive landed).
- [ ] Set exclusions so the sync engine doesn't try to fight ephemeral dirs.

## 9. Git and GitHub

Two scripts, each handles one concern. Both idempotent.

### Setup-Git: install git + apply repo gitconfig + set identity

```powershell
.\scripts\Setup-Git.ps1 -GitUserName 'Your Name' -GitUserEmail 'you@example.com'
# or
.\scripts\Setup-Git.ps1
# (with no params, prompts only if identity isn't already globally set)
```

- Installs git via winget if missing.
- Deploys `profiles/git/.gitconfig` to `$HOME/.gitconfig` while preserving any existing `user.name`/`user.email` (snapshot via `git config --global --get` → restore after overwrite).
- Sets identity if you passed params AND they differ from current; otherwise leaves alone.

### New-GitHubSshProfile: add an SSH key for a GitHub account

```powershell
.\scripts\New-GitHubSshProfile.ps1 -Email 'you@example.com'
# Default KeyAlias=id_ed25519_github, HostAlias=github.com.

# For a second account:
.\scripts\New-GitHubSshProfile.ps1 `
    -Email 'me@work.com' `
    -KeyAlias 'id_ed25519_work' `
    -HostAlias 'github.com-work'
```

- Generates an ed25519 key (skips if `~/.ssh/<KeyAlias>` already exists).
- Appends a `Host <HostAlias>` block to `~/.ssh/config` (skips if already present).
- Copies the public key to your clipboard and opens `https://github.com/settings/ssh/new` so you can paste.

Re-runnable per account — pick different KeyAlias/HostAlias each time.

See [`git-github.md`](git-github.md) for the multi-account URL trick, `includeIf` per-repo identity, and verification commands.

## 10. Run `bootstrap.ps1` (the workhorse)

Clone or copy this repo somewhere (e.g. `$env:USERPROFILE\code\windows-system-config`). Open an **elevated** PowerShell, `cd` into it, and run:

```powershell
.\bootstrap.ps1 -Verify     # dry-run first to confirm what'll happen
.\bootstrap.ps1             # full run
```

What it covers (each step idempotent, tag-filtered, logged):

- System restore point
- Win11Debloat (apps + telemetry + UI tweaks)
- O&O ShutUp10++ with the saved privacy config
- `tweaks.reg` (per-value import with detailed failure log)
- Time zone, taskbar autohide
- winget import (tiered — see below)
- Power plan + USB selective suspend + LSPM + timeouts
- Defender exclusions for dev/audio dirs
- Hyper-V / WSL / VMP / Sandbox features
- WSL Ubuntu install + `.wslconfig`
- Post-install hooks for each installed app (e.g. Notepad++ plugins, VS Code extensions)
- Windows Search service disabled (Everything covers file-name search; Outlook content search disabled — see [`debloat.md`](debloat.md))
- Profile deployment: PS profile / Windows Terminal settings / OMP theme / Caskaydia Cove fonts / AHK startup shortcut / `.gitconfig`
- A `TODO-post-install.txt` file on Desktop with anything that has to be done manually

**App tiers** — `bootstrap.ps1 -Tiers common,professional,personal` (default: all three). See [`../resources/winget/`](../resources/winget/) for the tier-file contents:

| Tier | What's in it |
|---|---|
| `common` | PowerShell 7, Git, gh, OhMyPosh, VS Code, PowerToys, .NET 10 SDK, Docker Desktop, Firefox, Chrome, Notepad++, Obsidian, Everything, Insync, 7zip, Bitwarden CLI, PDF24, AutoHotkey, VLC, WizTree, Logitech Options+, UniGetUI |
| `professional` | JetBrains Toolbox, SSMS, .NET 8 SDK (LTS), fnm, pyenv-win, WinMerge, WinSCP |
| `personal` | LatencyMon, REAPER, GeForce Now |

## 11. Windows Terminal, PowerShell, Oh-My-Posh

Profile files (PS profile, WT settings, OMP theme, fonts, AHK script) live in [`../profiles/`](../profiles/) and **deploy automatically as step `80-profiles` in the bootstrap run**. No extra command needed for the default flow.

For ad-hoc redeployment (e.g. after you edit a profile file in the repo), run the standalone script:

```powershell
.\scripts\Install-Profiles.ps1            # copy
.\scripts\Install-Profiles.ps1 -Symlink   # symlink (requires elevation or Dev Mode)
.\scripts\Install-Profiles.ps1 -WhatIf    # preview only
.\scripts\Install-Profiles.ps1 -Only git,pwsh   # just specific categories
```

See [`terminal-profile.md`](terminal-profile.md) for what each file does and where it lands.

## 12. Optionally install VS Code for markdown/script editing

(Already in `apps.common.json`; skip if `bootstrap.ps1` already ran with the `common` tier.)

## 13. Claude Code

```powershell
.\scripts\Install-ClaudeCode.ps1
```

Installs via winget and adds the install dir to user PATH.

## 14. Notepad++ + VS Code post-install hooks

Notepad++ is in `apps.common.json`, so it installs in step 10. The plugin sideload (`Compare`, `XML Tools`, etc.) runs automatically via the post-install hook at [`../post-install/Notepad++.Notepad++.ps1`](../post-install/Notepad++.Notepad++.ps1).

Same for VS Code: [`../post-install/Microsoft.VisualStudioCode.ps1`](../post-install/Microsoft.VisualStudioCode.ps1) installs a curated extension set after the apps step.

If you skip the apps step initially and want to re-run just the post-install hooks later:

```powershell
.\bootstrap.ps1 -Steps extras
```

## 15. Manual app installs / configuration

Some apps either aren't on winget, are version-pinned to a release winget doesn't carry, or need vendor-specific account setup that scripts can't automate. See also `TODO-post-install.txt` on the Desktop after `bootstrap.ps1`.

### Apps not on winget (or version-pinned)

- [ ] **Microsoft Office** — download via Office Deployment Tool from <https://www.microsoft.com/en-us/download/details.aspx?id=49117> with custom XML config (generate at <https://config.office.com>). Install Word / Excel / PowerPoint / Outlook, skip OneNote / Teams / Publisher / Skype. Activate by signing into Word > File > Account.
- [ ] **CoolerMaster MasterPlus+** — for MK750 keyboard customization. Download from <https://www.coolermaster.com/en-global/software/masterplus/>.
- [ ] **Guitar Pro 7.5** — winget only carries v8; if you specifically want 7.5, download from <https://www.guitar-pro.com/> (account required).
- [ ] **Native Instruments Guitar Rig** — install via **Native Access** from <https://www.native-instruments.com/en/specials/native-access-2/>, then use Native Access to install Guitar Rig.
- [ ] **Arturia keyboard software** — install via **Arturia Software Center** from <https://www.arturia.com/support/downloads&manuals>, then use ASC to install your specific keyboard's product page.

### Vendor / hardware drivers not in MyASUS Live Update

- [ ] **Audient EVO 4 driver** — download from <https://audient.com/products/audio-interfaces/evo-4/downloads/>. Ships ASIO + the EVO standalone mixer.

### Serbian eUprava (electronic government) tools

These all require a citizen ID card with chip (lična karta) and a USB smart-card reader. Install in this order:

- [ ] **Reader driver** — usually generic CCID-compliant; Windows finds it automatically. If yours needs vendor driver, install before card middleware.
- [ ] **TrustEdgeID** middleware — <https://www.eid.gov.rs/> (preuzimanje softvera). Required for card recognition.
- [ ] **Čelik** — official card reader app. <https://www.mup.gov.rs/wps/portal/sr/usluge/aplikacije/celik>.
- [ ] **ePorezi** — tax-portal client. <https://eporezi.purs.gov.rs/>.

### Manual settings and activation

- [ ] **Office activation** — sign in via Word → File → Account.
- [ ] **BitLocker** — intentionally not automated. Configure via Settings → System → Storage if desired.
- [ ] **BIOS settings double-check** — SVM / Secure Boot / fTPM enabled (see [`bios.md`](bios.md)).
- [ ] **Vendor app settings** — Battery Care, Fan Mode, etc. See your machine doc under [`machines/`](machines/).

## 16. After Windows feature updates

Feature updates (24H2 → 25H2 etc.) silently re-enable telemetry, Copilot, Widgets, web search, lock-screen suggestions, etc. Re-run:

```powershell
.\bootstrap.ps1 -PostUpdate
```

Equivalent to `-Steps debloat,privacy,features,power,defender`. Skips the slow apps step. About 60 seconds.

See [`post-update.md`](post-update.md) for which settings drift most often.
