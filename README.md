# win-setup

A personal Windows 11 base. Renders an `autounattend.xml` for unattended install, then re-applies registry tweaks / debloat / privacy / apps / power / Defender / WSL via an idempotent `bootstrap.ps1` — so a Windows feature update never silently erases the settings you spent an evening fixing.

Designed for .NET / WSL dev work, music production with an external audio interface, OLED preservation, and minimum Microsoft noise. Generic enough to fork; machine-specific quirks isolated under [`docs/machines/`](docs/machines/).

---

## Quick start

```powershell
# Clone somewhere — e.g. $env:USERPROFILE\code\win-setup
git clone https://github.com/<you>/win-setup
cd win-setup

# Dry-run first to see what would happen (no admin needed for parsing)
.\bootstrap.ps1 -Verify

# Full run (elevated PowerShell required)
.\bootstrap.ps1

# After a Windows feature update flipped settings back
.\bootstrap.ps1 -PostUpdate

# Only sync apps
.\bootstrap.ps1 -AppsOnly
```

For the procedural walkthrough — pre-install, drivers, activation, drives, scripts — see **[`docs/install-checklist.md`](docs/install-checklist.md)**.

For the why behind each piece, see **[`docs/setup-guide.md`](docs/setup-guide.md)**.

---

## Repo layout

```
win-setup/
├── bootstrap.ps1                  # Thin orchestrator: imports module, dot-sources steps/
├── lib/WinSetup/                  # Logging + helpers (Get-ResourcePath, Import-RegFilePerValue)
├── steps/                         # 00-preflight ... 80-profiles, runnable standalone
├── resources/                     # Input data consumed by steps
│   ├── autounattend/              #   - autounattend.xml template + renderer
│   ├── debloat/                   #   - Win11Debloat CustomAppsList.txt
│   ├── shutup/                    #   - O&O ShutUp10++ saved cfg
│   ├── registry/                  #   - tweaks.reg
│   └── winget/                    #   - apps.{common,dev,work,personal}.json
├── post-install/                  # Per-app hooks; named after winget package id
├── scripts/                       # Standalone interactive scripts (git/github, etc.)
├── profiles/                      # Windows Terminal / PS $PROFILE / Oh-My-Posh / .gitconfig
├── snippets/                      # Small PowerShell utility scripts
├── docs/                          # Topical docs (machine-agnostic)
│   └── machines/                  #   Machine-specific supplements
└── CLAUDE.md                      # Project guidance for Claude Code
```

---

## Step tags

Pre-flight (admin, network, OS build, exec policy) has no tags and **always runs**. Configurable steps:

| Tag | What it covers |
|---|---|
| `restore` | System restore point |
| `debloat` | Win11Debloat + OOSU10 + tweaks.reg |
| `privacy` | OOSU10 + tweaks.reg (subset of debloat) |
| `config` | tweaks.reg + `.wslconfig` |
| `core` | Most "every-run" settings (debloat, region, power, defender) |
| `power` | Power plan + USB suspend + LSPM + timeouts |
| `defender` | Defender exclusions |
| `apps` | winget source + tiered import + post-apps tweaks re-import |
| `extras` | `post-install/<package-id>.ps1` hooks for installed apps |
| `search` | Disable Windows Search service (Everything replaces it — see [`docs/debloat.md`](docs/debloat.md)) |
| `features` | Hyper-V / WSL / VMP / Sandbox |
| `wsl` | WSL kernel + Ubuntu + `.wslconfig` |
| `profiles` | Deploy `profiles/` files (PS profile, WT, OMP, fonts, AHK, `.gitconfig`) via `Install-Profiles.ps1` |
| `modules` | Install PowerShell modules consumed by the deployed PS profile (`z`, `Terminal-Icons`) |

Step runs if **any** of its tags is in your `-Steps` list.

Preset switches:

| Switch | Expands to |
|---|---|
| `-PostUpdate` | `-Steps debloat,privacy,features,power,defender` |
| `-AppsOnly` | `-Steps apps,extras` |
| `-Verify` | `-DryRun` |

App tier filter (independent of `-Steps`):

| Switch | Effect |
|---|---|
| `-Tiers common,dev,work,personal` | Default — import all four tier files |
| `-Tiers common` | Only `apps.common.json` (baseline, ~18 packages — browsers, OhMyPosh, Git, VS Code, etc.) |
| `-Tiers common,dev` | Baseline + dev runtimes (.NET SDK, Docker, gh, Bitwarden CLI) |
| `-Tiers common,dev,work` | + work tooling (JetBrains, SSMS, .NET LTS, fnm, pyenv, WinMerge, WinSCP) |
| etc. | Any combination of the four |

Force switches:

| Switch | Effect |
|---|---|
| `-ForceWslConfig` | Overwrite an existing `.wslconfig` (with backup) |
| `-ForceAppExtras` | Re-run every `post-install/<package-id>.ps1` regardless of content-hash sentinel |

---

## Idempotency guarantees

Safe to run repeatedly:

- **WSL data is never touched.** Ubuntu install only runs if Ubuntu isn't already registered. Existing home dir, projects, apt packages — all left alone.
- **`.wslconfig` is conservative by default.** If you've customized it by hand, bootstrap leaves it. Pass `-ForceWslConfig` to refresh from the repo template.
- **Registry, services, power, Defender, features** are all no-ops when desired state already holds.
- **Win11Debloat, OOSU10, `tweaks.reg`** are pure setters — applying them again is a no-op when current state already matches.
- **winget import** treats the apps lists as desired state: apps removed from the system but still listed in `apps.<tier>.json` WILL be reinstalled. Keep the lists honest, or filter via `-Tiers` / `-AppsOnly`.
- **Post-install hooks** are skipped when their content hasn't changed since the last successful run (SHA-256 sentinel at `%LocalAppData%\win-setup\post-install\<id>.hash`).

---

## Logs

Everything goes to `%USERPROFILE%\win-setup-logs\` with a shared `<yyyyMMdd-HHmmss>` stamp:

| File | What |
|---|---|
| `bootstrap-<stamp>.log` | Master log of every step |
| `winget-<stamp>.log` | Raw winget output |
| `oosu-<stamp>.log` | O&O ShutUp10++ stdout |
| `win11debloat-<stamp>.log` | Win11Debloat transcript |
| `reg-import-<stamp>.log` | Per-value tweaks.reg import (step 20) |
| `reg-import-post-apps-<stamp>.log` | Per-value re-import (step 60, post-winget) |

See [`docs/troubleshooting.md`](docs/troubleshooting.md) for common failures.

---

## Documentation map

- **[`docs/install-checklist.md`](docs/install-checklist.md)** — procedural walkthrough for a fresh install
- **[`docs/setup-guide.md`](docs/setup-guide.md)** — what the repo does and why; entry into the topical docs
- **[`docs/bios.md`](docs/bios.md)** — BIOS / UEFI baseline
- **[`docs/drivers.md`](docs/drivers.md)** — driver install order
- **[`docs/oled.md`](docs/oled.md)** — OLED preservation
- **[`docs/audio.md`](docs/audio.md)** — low-latency Windows audio + interface setup
- **[`docs/debloat.md`](docs/debloat.md)** — layered debloat philosophy + "don't remove" list
- **[`docs/wsl.md`](docs/wsl.md)** — WSL2 + `.wslconfig`
- **[`docs/post-update.md`](docs/post-update.md)** — re-running after Windows feature updates
- **[`docs/git-github.md`](docs/git-github.md)** — git setup + multi-account SSH
- **[`docs/terminal-profile.md`](docs/terminal-profile.md)** — terminal / PS profile / Oh-My-Posh
- **[`docs/troubleshooting.md`](docs/troubleshooting.md)** — logs, common failures
- **[`docs/machines/`](docs/machines/)** — machine-specific supplements
- **[`post-install/README.md`](post-install/README.md)** — per-app post-install hook convention
