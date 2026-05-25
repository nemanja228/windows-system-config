# Debloat philosophy

Why this repo strips Windows the way it does, and what NOT to strip. Applies to any Windows 11 install.

---

## Layered approach

Each layer fills gaps the previous one leaves. Same principle a build tool uses with optimization passes — each tool sees the previous tool's output and removes more.

1. **`autounattend.xml`** (image-level, before first boot) — strips Appx packages at install time. **Cleanest possible result** because the packages never run, never register, never write user-data dirs.
2. **Win11Debloat** (Raphire) — runs from `bootstrap.ps1` step `20-debloat` with `-RunDefaults -Silent`. Conservative defaults, apps + UI focused, well-maintained CLI mode.
3. **O&O ShutUp10++** — `OOSU10.exe ooshutup10.cfg /quiet`. Granular privacy toggles via a saved config. Generate the config interactively once via the UI (File → Export); apply silently forever after.
4. **`tweaks.reg`** — fills gaps the above tools miss: Copilot policy, advertising ID, lock-screen suggestions, Storage Sense, Edge preload, regional pack, dark mode, taskbar alignment, etc. Per-value imported by `Import-RegFilePerValue` so partial failures get visible reports.
5. **Group Policy (gpedit.msc)** — Pro/Enterprise-edition extras. Cloud Content, Search, AI features, Widgets. Most of these have HKLM mirrors that work for Home edition too; `tweaks.reg` covers them.

After bootstrap completes, step `60-apps` re-imports `tweaks.reg` to clean up context-menu entries that installers added during the apps step (Git Bash, "Open with Notepad", etc.).

---

## Rules I won't break

- **Do debloat on a fresh install** — not on a daily-driver months in. Some of the registry tweaks (file extensions, taskbar alignment, dark mode) are aggressive and will erase user customizations.
- **Don't use Tiny11 / NTLite** for a personal machine you depend on. They strip too aggressively, break .NET / WSL / WebView2, and can't be cleanly Windows-Updated forward through major releases.
- **Don't fully disable Defender** unless replacing it with another EDR. Windows Defender on Win11 24H2+ is genuinely competitive with paid AV for desktop use. Disable telemetry separately via OOSU10 / tweaks.reg.
- **Group Policy / registry to disable telemetry**, not killing the underlying service. Some apps poke `Microsoft.Diagnostics.Tracing` APIs and break loudly if the service is gone.
- **Save your debloat preset.** Major feature updates (24H2 → 25H2 etc.) revert many tweaks. Re-running `bootstrap.ps1 -PostUpdate` reapplies them in ~60s — but only if the preset (`apps.json`, `tweaks.reg`, `ooshutup10.cfg`) is saved.
- **Restore point before each major step.** `bootstrap.ps1` step `10-restore` does this automatically.

---

## What NOT to remove

| Don't remove | Why |
|---|---|
| `Microsoft.NET.*`, `.NETFramework` | .NET dev requirement. |
| `Microsoft.VCLibs.*` | Runtime for many Store apps. |
| `Microsoft.UI.Xaml.*` | Same — modern Windows app UI. |
| `Microsoft.Services.Store.Engagement` | Needed for Store updates to work. |
| `Microsoft.WindowsAppRuntime.*` | Modern Windows apps depend on this. |
| Microsoft Store | Unless you're certain you'll never want a Store app. Hard to reinstall cleanly. |
| Microsoft Edge | Can't fully remove anyway — half the OS embeds WebView2. Just disable startup boost / prelaunch (in `tweaks.reg`). |
| Windows Search service | Set to Manual or limit indexed paths instead. Stripping breaks Outlook search, taskbar search, file content search. |
| `Connected User Experiences and Telemetry` service | Disable telemetry via GPO/registry. Don't kill the service. |
| WebView2 Runtime | Many modern apps embed it (Teams, Outlook for Windows, GitHub Desktop, etc.). |

`resources/debloat/CustomAppsList.txt` is the source of truth for what Win11Debloat removes on this repo's behalf. Edit there, not in `bootstrap.ps1`.

---

## Windows Search (indexing) — optional full disable

Windows Search runs an indexer service (`SearchIndexer.exe`) that catalogs file content + metadata for the Start menu's file-search workflow, File Explorer's inline search bar, and Outlook's full-text content search.

The indexer is a persistent background workload. If you don't rely on those specific features, disabling it reclaims noticeable CPU + I/O at idle. Step `55-search.ps1` in `bootstrap.ps1` (tag `search`) does the disable.

### What still works after disabling

- App launch via Start ("Start, type filename" for **apps**, not for files — apps are in the registry, not the search index)
- **Everything** (voidtools — in `apps.common.json`) — reads the NTFS Master File Table directly, ignores Windows Search entirely. This is the replacement for file-name search.
- Raw filesystem access (`Get-ChildItem`, `ripgrep`, etc.)
- IDE workspace search (VS Code, JetBrains, Notepad++ all maintain their own indexes)

### What stops working

- **Start menu file search** — typing a filename in Start returns no file results.
- **File Explorer inline search bar** — slow on non-indexed paths; effectively useless on big directory trees.
- **Outlook content search** — falls back to a slow per-message scan when you search inside email bodies. Sender/subject search still works.
- **Cortana / search highlights** — already neutered by `tweaks.reg` regardless.

### How to apply

Default `bootstrap.ps1` runs **every** step regardless of tag, so the search-disable step DOES execute unless you filter it out. To explicitly skip while running the rest:

```powershell
.\bootstrap.ps1 -Steps core,apps,wsl,profiles      # any tag list that excludes 'search'
```

To run **only** the search disable on an existing system:

```powershell
.\bootstrap.ps1 -Steps search
```

To re-enable Windows Search later, undo the step manually:

```powershell
Set-Service -Name WSearch -StartupType Automatic
Start-Service -Name WSearch
```

If you discover after the fact that you actually do rely on Outlook content search, this re-enable is non-destructive — the existing index is preserved on disk and the service picks up where it left off.

---

## Office-specific

- **Install via Office Deployment Tool** (<https://learn.microsoft.com/en-us/deployoffice/overview-office-deployment-tool>) with a custom XML config. Generate the config at <https://config.office.com>. Include Word / Excel / PowerPoint / Outlook only; skip OneNote / Teams / Publisher / Skype unless needed.
- **Per-app: File → Options → Trust Center → Privacy Options** → disable "Optional connected experiences" and "Send data about how you use Office."
- **Semi-Annual Channel** if you want fewer surprise feature changes. Current Channel (Monthly) is the default.
