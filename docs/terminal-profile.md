# Windows Terminal + PowerShell + Oh-My-Posh

How `profiles/` works and how `scripts/Install-Profiles.ps1` deploys files into their real OS locations.

> **Status:** Phase 5 in the restructure plan. The `profiles/` directory exists with placeholder files; the `Install-Profiles.ps1` script lands in Phase 5. This doc is the contract — actual content will come from your existing setup once you paste it in.

---

## What's where

| Repo path | Deploys to | Notes |
|---|---|---|
| `profiles/windows-terminal/settings.json` | `%LocalAppData%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json` | Single Windows Terminal config. App reads this live, no restart needed. |
| `profiles/powershell/Microsoft.PowerShell_profile.ps1` | `$PROFILE.CurrentUserAllHosts` (typically `~\Documents\PowerShell\profile.ps1` for PS 7+, or `~\Documents\WindowsPowerShell\` for 5.1) | Sourced at every PS session start. |
| `profiles/oh-my-posh/theme.omp.json` | `%LocalAppData%\oh-my-posh\theme.omp.json` (path is your choice — PS profile references it) | OMP prompt theme. |
| `profiles/git/.gitconfig` | `~/.gitconfig` | Global git config. Also handled by `Setup-Git.ps1` (which delegates to `Install-Profiles.ps1 -Only git` internally). Identity (`user.name`/`user.email`) is preserved across the deploy. |

---

## `Install-Profiles.ps1` contract

```powershell
.\scripts\Install-Profiles.ps1            # copy each profile file to its OS target
.\scripts\Install-Profiles.ps1 -Symlink   # symlink instead (requires elevation on Windows)
.\scripts\Install-Profiles.ps1 -WhatIf    # show what would happen, change nothing
```

What it does:

1. Enumerates each `profiles/<subfolder>/` entry.
2. Resolves the target path per OS conventions (Windows Terminal LocalState, PowerShell `$PROFILE`, etc.).
3. **Backs up any existing target** with `.bak-<stamp>` suffix before overwriting.
4. Copies (default) or symlinks (`-Symlink`) the repo file to the target.
5. Logs everything via the `WinSetup` module's `Write-Log` (so output shows up in the bootstrap log if invoked from there).

**Symlink mode** is convenient for `profiles/` — edits to the repo file show up live in the target. But Windows symlinks need either elevation OR Developer Mode enabled. The script detects which is available and falls back to copy if neither.

`Install-Profiles.ps1` does NOT modify your existing profile content — if you want to keep parts of an existing `Microsoft.PowerShell_profile.ps1` and merge in repo additions, that's a manual edit.

---

## Why these particular files?

- **Windows Terminal `settings.json`** — color schemes, fonts, key bindings, profile list (PowerShell, WSL Ubuntu, cmd, etc.). Versioning this is the only sane way to keep terminal config consistent across machines.
- **PowerShell profile** — Oh-My-Posh init, module imports, aliases, helper functions. This is where small workflow customizations live (custom prompt info, project navigation, etc.).
- **OMP theme** — visual prompt design. Lots of community themes; you can build your own at <https://ohmyposh.dev/docs/themes>. Reference the theme path from your PS profile:

  ```powershell
  oh-my-posh init pwsh --config "$env:LocalAppData\oh-my-posh\theme.omp.json" | Invoke-Expression
  ```

---

## Cross-shell prompt

Oh-My-Posh works in PowerShell, bash, zsh, fish, etc. Same theme JSON, different init line per shell:

```bash
# bash
eval "$(oh-my-posh init bash --config /path/to/theme.omp.json)"

# zsh
eval "$(oh-my-posh init zsh --config /path/to/theme.omp.json)"

# fish
oh-my-posh init fish --config /path/to/theme.omp.json | source
```

In WSL, point the theme path at the Windows-side file via `/mnt/c/Users/<you>/AppData/Local/oh-my-posh/theme.omp.json`. Edit once, both sides update.

---

## When to re-run `Install-Profiles.ps1`

- After editing any `profiles/<subfolder>/` file in the repo, if you copied instead of symlinked.
- After a Windows feature update wipes anything (rare for these files — the target paths are user-data, not OS-managed).
- When setting up a new machine.

If you symlinked, no re-run needed — the link still points at the repo file.
