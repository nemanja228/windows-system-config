# Setup guide

A clean Windows 11 setup focused on .NET / WSL dev work, music production with an external audio interface, OLED preservation, and minimum Microsoft noise. Designed to be **idempotent** — re-runnable after a Windows feature update to recover from settings drift in ~60 seconds.

This page is the overview. Each topic has its own doc; follow the links.

---

## What this repo gets you

- A rendered `autounattend.xml` that handles Windows Setup unattended: skips OOBE, creates a local account, denies telemetry, removes Appx packages before first boot.
- A `bootstrap.ps1` orchestrator: applies registry tweaks, OOSU10 privacy config, debloat, power plan, Defender exclusions, Hyper-V/WSL/Sandbox features, WSL Ubuntu install, and deploys your profile files (terminal, PS, OMP, fonts, AHK, .gitconfig).
- A tiered apps list (`apps.common.json` + `apps.dev.json` + `apps.work.json` + `apps.personal.json`) imported via winget.
- Per-app post-install hooks (`post-install/<package-id>.ps1`) — install extensions, sideload plugins, etc.
- A homed `.gitconfig`, SSH multi-account setup helper, Windows Terminal / PowerShell `$PROFILE` / Oh-My-Posh placeholders.
- Re-runnable indefinitely. Every step is idempotent. After a Windows feature update: `.\bootstrap.ps1 -PostUpdate`.

---

## Where to go next

**To actually install Windows from scratch**, follow the procedural walkthrough:

- [`install-checklist.md`](install-checklist.md) — step-by-step: pre-install, drivers, activation, drives, scripts.

**To understand individual decisions** ("why does this repo do X?"), each topic has a focused doc:

| Topic | Doc |
|---|---|
| BIOS / UEFI baseline (SVM, Secure Boot, fTPM, etc.) | [`bios.md`](bios.md) |
| Driver install order (vendor app first) | [`drivers.md`](drivers.md) |
| OLED preservation strategy | [`oled.md`](oled.md) |
| Low-latency audio + EVO 4 setup | [`audio.md`](audio.md) |
| Layered debloat philosophy | [`debloat.md`](debloat.md) |
| WSL2 setup + `.wslconfig` | [`wsl.md`](wsl.md) |
| Re-running after Windows feature updates | [`post-update.md`](post-update.md) |
| Git + GitHub SSH + in-repo `.gitconfig` | [`git-github.md`](git-github.md) |
| Windows Terminal / PowerShell `$PROFILE` / OMP | [`terminal-profile.md`](terminal-profile.md) |
| Logs, common failures, `Test-RegImport.ps1` | [`troubleshooting.md`](troubleshooting.md) |

**For machine-specific tweaks** (vendor apps, panel quirks, dock issues):

- [`machines/`](machines/) — one file per machine. Generic docs hold the bulk; only hardware-specific bits land there.

---

## The three install layers

```
┌────────────────────────────────────────────────────────────────────┐
│  1. autounattend.xml — runs during Windows Setup, before login.   │
│     Skips OOBE, creates local account, removes Appx packages,     │
│     applies baseline telemetry settings, partitions disk.         │
└──────────────────────────────┬─────────────────────────────────────┘
                               │ (first boot, first logon)
                               ▼
┌────────────────────────────────────────────────────────────────────┐
│  2. First-logon script (embedded in autounattend.xml) — pulls     │
│     down this repo, launches bootstrap.ps1 elevated.              │
│     (Manual today; can be automated once you publish the repo.)   │
└──────────────────────────────┬─────────────────────────────────────┘
                               │
                               ▼
┌────────────────────────────────────────────────────────────────────┐
│  3. bootstrap.ps1 — tag-filtered, idempotent. Runs:               │
│     - Restore point                                                │
│     - Win11Debloat (apps + telemetry + UI)                        │
│     - O&O ShutUp10++ with saved config                            │
│     - tweaks.reg (per-value import)                               │
│     - Time zone + taskbar autohide                                │
│     - Power plan + USB suspend + LSPM + timeouts                  │
│     - Defender exclusions for dev/audio folders                   │
│     - winget import of tiered apps lists                          │
│     - Post-install/<package-id>.ps1 hooks for installed apps      │
│     - tweaks.reg re-import (cleans up installer-created junk)     │
│     - Windows features + WSL Ubuntu + .wslconfig                  │
│     - profiles/ deployed via 80-profiles → Install-Profiles.ps1   │
└────────────────────────────────────────────────────────────────────┘
```

Once everything is set up, a fresh install is **plug in USB → wait → log in → run bootstrap → done**. After a Windows feature update months later, re-running `bootstrap.ps1 -PostUpdate` re-applies everything in ~60 seconds.

---

## What this repo intentionally doesn't do

- **BitLocker setup** — skipped for personal use; opinionated decision, not a hostility.
- **BIOS update** — manual via vendor app or support site. Bootstrap warns if BIOS feels out of date but doesn't flash.
- **Vendor app configuration** (MyASUS Battery Care, fan modes, etc.) — UI-only, no PowerShell API. See your machine doc.
- **Office activation** — sign in via Word > Account.
- **Audio interface driver install** (Audient EVO 4 etc.) — manual download from the vendor.

Full list in [`install-checklist.md`](install-checklist.md) § 15 ("Manual app installs / configuration").

---

## Versioning + drift

This repo is designed to be cloned and lived in. If you fork it for your own setup:

- Keep `bootstrap.ps1`, `lib/WinSetup/`, `steps/` as-is unless adding new steps.
- Customize `apps.<tier>.json`, `tweaks.reg`, `ooshutup10.cfg`, `CustomAppsList.txt` to taste.
- Add new entries to `post-install/<package-id>.ps1` per app.
- Add new machines to `docs/machines/`.

Re-running `bootstrap.ps1` is the canonical way to apply changes. The hash sentinel mechanic in step `61-app-extras` only re-runs hooks whose content actually changed; everything else is full-pass cheap because all the underlying state checks are local.
