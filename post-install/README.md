# post-install/

Per-app post-install hooks. Each file is a self-contained `.ps1` that runs **after** `winget install` has placed the matching app on disk.

## Naming convention

```
post-install/<exact-winget-package-id>.ps1
```

Examples:

| Package id | Hook file |
|---|---|
| `Notepad++.Notepad++` | `post-install/Notepad++.Notepad++.ps1` |
| `Microsoft.VisualStudioCode` | `post-install/Microsoft.VisualStudioCode.ps1` |
| `JanDeDobbeleer.OhMyPosh` | `post-install/JanDeDobbeleer.OhMyPosh.ps1` |

The bootstrap step `steps/61-app-extras.ps1` derives the package id from the filename (strips `.ps1`) and only runs the hook if `winget list --id <id> --exact` reports it as installed.

Dots in package ids and `++` in `Notepad++` are valid NTFS filename characters — no escaping needed.

## When hooks run

- **During `bootstrap.ps1`**: step `61-app-extras` runs immediately after step `60-apps` (winget import + post-apps tweaks re-import). Default tier set installs everything in `apps.{common,professional,personal}.json`, so any matching hook fires automatically.
- **Ad hoc**: `.\bootstrap.ps1 -Steps extras` runs only this step. Useful after installing an app manually (e.g. `winget install Notepad++.Notepad++` then `.\bootstrap.ps1 -Steps extras`).
- **Forced re-run**: `.\bootstrap.ps1 -ForceAppExtras` clears all sentinels first, so every hook fires.

## Idempotency contract

**Every hook must be safe to re-run.** The hash sentinel (see below) is a performance optimization, not a correctness guarantee — it only prevents the hook from running again if the script content hasn't changed. If a user re-installs the app or edits config outside the hook, the hook still has to do the right thing.

Common idempotency patterns:

- Test for existence before creating (`if (-not (Test-Path $target)) { ... }`).
- Use winget's own idempotency (`winget install` of an already-installed app is a no-op).
- For VS Code extensions: `code --install-extension <id>` returns 0 if already installed.
- For file copies: compare hashes before overwriting, or accept the overwrite as cheap.

Look at `Notepad++.Notepad++.ps1` for a reference implementation (per-plugin `Test-Path` skip).

## Hash-sentinel mechanic

Sentinels live at:

```
%LocalAppData%\win-setup\post-install\<package-id>.hash
```

Each `.hash` file is a single line: the SHA-256 of the hook script content (UTF-8 bytes).

On every bootstrap run:

1. The scanner enumerates `post-install/*.ps1`.
2. For each, it derives the package id and checks `winget list --id <id> --exact`.
3. If installed, it hashes the script content and compares against the sentinel.
4. **Hash matches** → skip (DEBUG log line, no work done).
5. **Hash differs or sentinel missing** → run via `Invoke-Step`, write the new hash on success.

If the hook fails, the sentinel is **not** written — the hook retries on the next run.

`-ForceAppExtras` deletes every sentinel before scanning, so every hook re-runs once.

## What a hook script looks like

Minimal skeleton:

```powershell
# post-install/My.PackageId.ps1
#
# Runs after winget installs My.PackageId. Bootstrap's 61-app-extras step
# scans this folder and runs hooks for installed apps.
#
# Must be idempotent — runs on first install AND any time the script content
# changes (hash sentinel triggers re-run on edits).

# do whatever extra setup the app needs:
# - install extensions
# - copy a settings file from profiles/
# - tweak a registry key
# - download a plugin pack
# - whatever

Write-Host "My.PackageId post-install: doing things..." -ForegroundColor Cyan

# ... your setup ...

Write-Host "My.PackageId post-install: done." -ForegroundColor Green
```

The hook runs inside an `Invoke-Step -ContinueOnError -SkipOnDryRun` wrapper, so:

- Exceptions are logged but don't abort bootstrap.
- During `-Verify` / `-DryRun`, the hook is skipped entirely (sentinel untouched).
- Output is captured and color-coded into the bootstrap log.
- A non-zero `$LASTEXITCODE` from any native call inside the hook is treated as failure.

## Things hooks should NOT do

- **Install the app itself.** That's `step 60-apps` or `apps.<tier>.json`. Hooks assume the app is already installed.
- **Long-running blocking work.** If you need a background download, log it and let it continue async — bootstrap won't wait gracefully on stuck hooks.
- **Prompt for input.** Hooks run non-interactively. Read config from somewhere known (env var, file in `profiles/`, hardcoded sensible default).
- **Modify other apps' state.** One hook per app, single responsibility.
