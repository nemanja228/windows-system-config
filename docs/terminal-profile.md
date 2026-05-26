# Windows Terminal + PowerShell + Oh-My-Posh

How `profiles/` is laid out and how it lands on disk via `scripts/Install-Profiles.ps1` (and, transitively, the bootstrap steps `80-profiles` + `85-ps-modules`).

The authoritative per-file reference lives in [`../profiles/README.md`](../profiles/README.md). This doc is the why and how-it-fits-together view.

---

## What's where

| Repo path | Deploys to | Notes |
|---|---|---|
| `profiles/windows-terminal/settings.json` | `%LocalAppData%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json` | Minimal JSONC. `profiles.list` intentionally omitted — WT auto-detects PowerShell, WSL distros, dev shells. Per-profile defaults (font, scheme, opacity) in `profiles.defaults`. |
| `profiles/powershell/Microsoft.PowerShell_profile.ps1` | Both `~\Documents\PowerShell\` (pwsh 7+) **and** `~\Documents\WindowsPowerShell\` (PS 5.1) | Hard-targets both host dirs so the profile loads in either. PSReadLine 2.2+ features are gated behind `$PSVersionTable` checks. |
| `profiles/oh-my-posh/winsetup.omp.json` | `%LocalAppData%\oh-my-posh\themes\winsetup.omp.json` | OMP theme. v3-compatible glyphs (FontAwesome instead of post-BMP MDI codepoints). PS profile references it by name. |
| `profiles/fonts/CaskaydiaCoveNerdFontMono-*.ttf` | `%WINDIR%\Fonts\` + registered in `HKLM\…\Fonts` | Required by OMP theme and WT default font. Install needs elevation (HKLM write). Never symlinked — the Shell COM font API needs a real file. |
| `profiles/autohotkey/WtTransparent.ahk` | Stays in the repo; startup shortcut in `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\WtTransparent.lnk` points at it | AHK v2 — toggles window transparency. Auto-launches on logon. |
| `profiles/git/.gitconfig` | `~/.gitconfig` | Identity-free; `user.name`/`user.email` are preserved across redeploys (snapshot via `git config --global --get` → restore after copy). Always copied, never symlinked, to avoid leaking identity into the repo. |

---

## How it gets deployed

Three entry points, same payload:

```powershell
# 1. Full bootstrap — step 80 invokes Install-Profiles.ps1 -NoInit, step 85 installs PS modules
.\bootstrap.ps1

# 2. Just the profile-related steps
.\bootstrap.ps1 -Steps profiles,modules

# 3. Standalone — interactive script, own log file + summary
.\scripts\Install-Profiles.ps1
.\scripts\Install-Profiles.ps1 -Symlink             # link instead of copy (needs elevation or Dev Mode)
.\scripts\Install-Profiles.ps1 -Only pwsh,omp       # subset
.\scripts\Install-Profiles.ps1 -WhatIf              # preview
```

What `Install-Profiles.ps1` does for each of its six categories (`git`, `pwsh`, `omp`, `wt`, `fonts`, `ahk`):

1. Resolves the OS target path.
2. Backs up any existing target as `<target>.bak-<stamp>` (skip with `-Force`).
3. Copies (default) or symlinks (`-Symlink`) the repo file into place.
4. Logs through the `WinSetup` module — when invoked from bootstrap via `-NoInit`, each category lands as its own row in the bootstrap summary.

Symlink mode is convenient for active profile development (edits in the repo show up live in the target), but Windows symlinks need either elevation OR Developer Mode. The script falls back to copy with a WARN if neither is available. Fonts and `.gitconfig` are always copied regardless of `-Symlink`.

---

## Module prerequisites (step `85-ps-modules`)

The deployed PS profile imports `z` (directory jumper) at load time and lazy-loads `Terminal-Icons` on first `ls`. Neither ships with Windows or pwsh, so step 85 installs them:

1. Marks `PSGallery` as `Trusted` (avoids the interactive confirm on `Install-Module`).
2. Installs `z` and `Terminal-Icons` to `CurrentUser` scope if not already present.

No elevation needed for `-Scope CurrentUser`. Skipped per-module when `Get-Module -ListAvailable` already shows the module.

Standalone equivalent:

```powershell
Install-Module z,Terminal-Icons -Scope CurrentUser
```

---

## Cross-shell OMP

Oh-My-Posh works in PowerShell, bash, zsh, fish. Same theme JSON, different init line per shell:

```bash
# bash
eval "$(oh-my-posh init bash --config "$LOCALAPPDATA/oh-my-posh/themes/winsetup.omp.json")"

# zsh
eval "$(oh-my-posh init zsh --config "$LOCALAPPDATA/oh-my-posh/themes/winsetup.omp.json")"

# fish
oh-my-posh init fish --config "$LOCALAPPDATA/oh-my-posh/themes/winsetup.omp.json" | source
```

In WSL, point the theme path at the Windows-side file via `/mnt/c/Users/<you>/AppData/Local/oh-my-posh/themes/winsetup.omp.json`. Edit once, both sides update.

---

## When to re-run

- **After editing any `profiles/<subfolder>/` file in the repo, if you copied instead of symlinked.** Re-run `Install-Profiles.ps1` (optionally `-Only <category>` to be surgical).
- **After a Windows feature update** — rare for these files (the target paths are user-data, not OS-managed), but `bootstrap.ps1 -Steps profiles` is a one-liner if anything got disturbed.
- **On a new machine** — full `bootstrap.ps1` handles it via steps 80 + 85.

If you symlinked, no re-run is needed after editing — the link still points at the repo file. Restart the shell (or reload `$PROFILE`) to pick up profile changes; reload Windows Terminal settings live (no restart needed); restart the AHK process to pick up `.ahk` edits.
