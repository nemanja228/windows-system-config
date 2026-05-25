# After a Windows feature update

Major Windows updates (24H2 → 25H2, etc.) silently re-enable a depressing list of things you turned off. This repo is designed to make recovery a one-liner.

---

## What gets re-enabled

What I've seen across feature updates on my machines:

- **Copilot** — re-enabled as an Edge sidebar and a Win+C shortcut.
- **Widgets** (the news/weather thing in the taskbar) — re-added even if the Appx is gone.
- **Web search in Start** — Bing results come back to Start menu.
- **Cortana/voice search prompts** — even with Cortana removed.
- **Lock screen suggestions / spotlight** — re-enabled.
- **Telemetry level** — bumped back from Security to Basic, sometimes Enhanced.
- **Suggested apps on Start** — back as "ContentDeliveryManager" entries.
- **Edge first-run / startup boost / preload** — re-enabled.
- **Recall** (on supported hardware) — may be re-offered through OOBE-style prompts.
- **OneDrive autostart** — re-enabled, file-explorer integration re-added.

Sometimes settings (file extensions visible, taskbar alignment, dark mode) survive; sometimes they don't. It's worth re-running everything to be sure.

---

## The fix

```powershell
cd $env:USERPROFILE\code\windows-system-config   # or wherever you cloned
.\bootstrap.ps1 -PostUpdate
```

`-PostUpdate` expands to `-Steps debloat,privacy,features,power,defender`. Runs:

- Win11Debloat (apps + UI tweaks)
- OOSU10 with the saved cfg
- `tweaks.reg` per-value import
- Windows features (verifies Hyper-V / WSL / VMP / Sandbox are still enabled)
- Power plan + USB suspend + LSPM + timeouts
- Defender exclusions

Skipped: restore point, apps (no need to reinstall), WSL config (probably untouched by the update), profile deployment (your local edits to the deployed files survive — re-run `.\scripts\Install-Profiles.ps1` only if you've updated something in `profiles/` in the repo).

Takes about 60 seconds on a quiet machine. **Idempotent** — every step checks current state before changing anything.

---

## Less aggressive options

Sometimes you don't want a full re-apply. Cherry-pick by tag:

```powershell
# Just privacy + tweaks.reg
.\bootstrap.ps1 -Steps privacy

# Just power and Defender
.\bootstrap.ps1 -Steps power,defender

# Just verify what would change without changing anything
.\bootstrap.ps1 -PostUpdate -Verify
```

`-Verify` is `-DryRun` with a friendlier name — every step logs what it *would* do, nothing executes. Use it as the first run after a major update to see the delta.

---

## What this won't fix

Some things drift on every feature update and `bootstrap.ps1` can't help:

- **Custom right-click context menu entries** that some apps re-register on update. `tweaks.reg` removes the common offenders (Git Bash, Open-with-Notepad); bootstrap step `60-apps` re-applies it after the apps step to clean up entries the installers added back. But novel apps that you've added since the last update need their context-menu cleanup added to `tweaks.reg`.
- **App-specific settings** that the app stores in its own location and resets on its own update — those need their own re-apply logic (see `post-install/` for the per-app hook convention).
- **Pinned taskbar icons** sometimes get re-shuffled. Manual fix.
- **MyASUS / vendor app preferences** — these are app state, not OS state. The vendor app's update flow occasionally resets them; redo via the vendor app UI per `docs/machines/<this-machine>.md`.

---

## Optional: scheduled re-apply

If you want to defend against silent drift between feature updates (some updates are sneakier than others), schedule a weekly `tweaks.reg` pass:

```powershell
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument '-NoProfile -WindowStyle Hidden -File "C:\Users\<you>\code\windows-system-config\bootstrap.ps1" -Steps privacy'

$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At '3am'

Register-ScheduledTask -TaskName 'win-setup-weekly-tweaks' -Action $action -Trigger $trigger `
    -RunLevel Highest -Description 'Re-apply privacy tweaks.reg weekly'
```

Probably overkill for most people. The `-PostUpdate` run after a feature update is sufficient in practice.
