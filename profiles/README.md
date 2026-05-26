# profiles/

Personal user-level config files. Deployed into their real OS locations by [`../scripts/Install-Profiles.ps1`](../scripts/Install-Profiles.ps1).

The repo holds the *source* version of each file; the installer copies (or symlinks with `-Symlink`) into the standard Windows / app locations. Existing files are backed up to `<target>.bak-<stamp>` unless you pass `-Force`.

```powershell
.\scripts\Install-Profiles.ps1               # default: copy
.\scripts\Install-Profiles.ps1 -Symlink      # symlinks (needs elevation or Developer Mode)
.\scripts\Install-Profiles.ps1 -WhatIf       # preview only
.\scripts\Install-Profiles.ps1 -Only git,pwsh  # just these categories
```

## Categories

### `git/.gitconfig`

Global git config (no `[user]` block — identity is set live by `scripts/Setup-Git.ps1` so this file stays shareable). When deployed via `Install-Profiles.ps1` or step `80-profiles`, existing `user.name`/`user.email` in `~/.gitconfig` are snapshotted via `git config --global --get` before the overwrite and restored after — running the deploy never wipes identity.

Target: `$HOME\.gitconfig`

Highlights: `init.defaultBranch = main`, rebase on pull, autoSetupRemote, zdiff3 conflict style, histogram diff, rerere, fsckobjects everywhere, semantic version tag sorting.

### `powershell/Microsoft.PowerShell_profile.ps1`

PowerShell profile — generic, no personal identifiers. Sourced on every shell start.

Target: `$PROFILE.CurrentUserAllHosts` (typically `~\Documents\PowerShell\profile.ps1` for pwsh 7+).

What it sets up:

- PSReadLine + lazy-loaded Terminal-Icons (cost moves from every shell to first `ls`)
- Oh-My-Posh prompt (reads `profiles/oh-my-posh/winsetup.omp.json` after deployment)
- Argument completers: `winget`, `dotnet`, and a custom `git` completer (subcommand + branch completion) that replaces `posh-git` — ~700ms saved at startup
- PSReadLine bindings: UpArrow/DownArrow history search, smart insert/delete for quotes/parens/braces, F7 history GridView, Ctrl+V paste-as-here-string, RightArrow accepts next predicted word
- PSReadLine prediction (`ListView` over history)
- `Import-Module z` (zoxide-style directory jumper) — the `z` and `Terminal-Icons` modules are installed automatically by bootstrap step `85-ps-modules` (tag `modules`); install standalone with `Install-Module z,Terminal-Icons -Scope CurrentUser`
- `'git cmt' → 'git commit'` autocorrect
- `$wshell.SendKeys("^+]")` at the end — triggers the `WtTransparent.ahk` hotkey so every new PS window opens transparent. Drop this line if it conflicts with another app's binding.

### `oh-my-posh/*.omp.json`

OMP prompt themes. Currently one: `winsetup.omp.json`.

Target: `$env:LocalAppData\oh-my-posh\themes\<name>.omp.json`

The PS profile references `winsetup.omp.json` by name. To swap visuals, change the filename in the profile's OMP init line or drop a different theme in here.

### `windows-terminal/settings.json`

Windows Terminal settings (JSONC — `//` comments supported).

Target: `$env:LocalAppData\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json`

Generic / portable — `profiles.list` is intentionally NOT in this file. Windows Terminal auto-detects PowerShell, WSL distros, Visual Studio dev shells, Azure Cloud Shell at launch and merges them into the in-memory profile list. Per-profile defaults (font, scheme, cursor, opacity) live in `profiles.defaults` and apply to every auto-detected profile.

Highlights: `CaskaydiaCove Nerd Font Mono` (size 14), Tango Dark scheme, bar cursor, `Ctrl+T/W/N/Shift+W` for tab/pane management, several default key combos unbound to keep PSReadLine happy.

### `fonts/*.ttf`

Caskaydia Cove Nerd Font Mono — 4 weights (Regular, Bold, Italic, BoldItalic).

Target: `%WINDIR%\Fonts\` + registered in `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts`

Required by the OMP theme and the WT default font face. Install requires elevation (HKLM write).

Font fetched from <https://github.com/ryanoasis/nerd-fonts/releases/latest> → `CascadiaCode.zip`. Refresh:

```powershell
# Re-download the latest release and replace these files
$tmp = Join-Path $env:TEMP "nerd-fonts-refresh"
New-Item $tmp -ItemType Directory -Force | Out-Null
Invoke-WebRequest 'https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaCode.zip' -OutFile "$tmp\CascadiaCode.zip"
Expand-Archive "$tmp\CascadiaCode.zip" -DestinationPath $tmp
Get-ChildItem $tmp -Recurse -Filter 'CaskaydiaCoveNerdFontMono-*.ttf' |
    Where-Object { $_.Name -match '-(Regular|Bold|Italic|BoldItalic)\.ttf$' } |
    Copy-Item -Destination 'profiles\fonts\' -Force
Remove-Item $tmp -Recurse -Force
```

### `autohotkey/WtTransparent.ahk`

AutoHotkey **v2** script — window transparency via global hotkeys.

- `Ctrl + Shift + ]` — toggle current window between transparent (default level 210/255) and opaque
- `Ctrl + Win + =` — increase opacity by 10
- `Ctrl + Win + -` — decrease opacity by 10

Target: stays in the repo. `Install-Profiles.ps1` creates a shortcut in `$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\WtTransparent.lnk` pointing at the repo file. Windows opens .ahk files with the registered AHK v2 runtime (installed via `AutoHotkey.AutoHotkey` in `apps.common.json`).

Auto-launches on every logon. Edit the script in the repo; Restart-Computer or kill+restart the AHK process to pick up changes.

## Conventions

- All profile files are generic. No personal identifiers (`user.name`, machine-specific paths, GUIDs). Identity lands at deploy time, not commit time.
- Backups are kept indefinitely — clean up `.bak-<stamp>` files in target dirs when you trust the repo version.
- Symlink mode is ideal for active development on profile files — edits in the repo show up immediately in the target. Requires elevation or Windows Developer Mode.
- Fonts are NEVER symlinked. The Shell COM font-install API needs a real file. Re-running `Install-Profiles.ps1 -Only fonts` is a no-op if the font is already registered (idempotent).
