# Git and GitHub

Three concerns, three entry points — each idempotent, each does one thing well.

| You want to... | Use |
|---|---|
| Install git + apply repo gitconfig + set identity (first-time OR routine sync) | [`scripts/Setup-Git.ps1`](../scripts/Setup-Git.ps1) |
| Add a new GitHub SSH profile (reusable per account) | [`scripts/New-GitHubSshProfile.ps1`](../scripts/New-GitHubSshProfile.ps1) |
| Just refresh `~/.gitconfig` from the repo (identity preserved) | `Install-Profiles.ps1 -Only git` (also runs as part of bootstrap) |

---

## Setup-Git.ps1 — install + gitconfig + identity

Run on first install, or any time after — fully idempotent. No mandatory parameters.

```powershell
.\scripts\Setup-Git.ps1
# Install git if missing; deploy repo gitconfig (preserves existing identity);
# prompt for name/email only if neither already set globally.

.\scripts\Setup-Git.ps1 -GitUserName "Nemanja Raković" -GitUserEmail "me@example.com"
# Same but identity values come from params instead of prompts.

.\scripts\Setup-Git.ps1 -Force
# Re-run winget upgrade, overwrite gitconfig, re-set identity even if unchanged.
```

What's idempotent and how:

| Step | Skip condition |
|---|---|
| `winget install Git.Git` | git already on PATH (unless `-Force`) |
| gitconfig deploy | Always copies (cheap), but **preserves `user.name`/`user.email` across the overwrite** by snapshotting via `git config --global --get` before and `--set` after |
| identity write | New value matches current (unless `-Force`) |
| identity prompt | Skipped if either `-GitUserName`/`-GitUserEmail` provided OR already set globally |

The gitconfig deploy delegates to `Install-Profiles.ps1 -Only git -NoInit`, so the same machinery + identity preservation runs whether you invoked `Setup-Git`, `Install-Profiles`, or full `bootstrap.ps1` step `80-profiles`.

## New-GitHubSshProfile.ps1 — per-account SSH

Generates an ed25519 key, appends a `Host` block to `~/.ssh/config`, copies the public key to your clipboard, opens GitHub's SSH-keys page so you can paste.

Reusable: pick distinct `-KeyAlias` and `-HostAlias` per GitHub account.

```powershell
# Primary account (default KeyAlias=id_ed25519_github, HostAlias=github.com)
.\scripts\New-GitHubSshProfile.ps1 -Email 'me@personal.com'

# Secondary account — distinct key file + URL alias
.\scripts\New-GitHubSshProfile.ps1 `
    -Email 'me@work.com' `
    -KeyAlias 'id_ed25519_work' `
    -HostAlias 'github.com-work'

# A different host entirely (e.g. GitLab)
.\scripts\New-GitHubSshProfile.ps1 `
    -Email 'me@gitlab.com' `
    -KeyAlias 'id_ed25519_gitlab' `
    -HostAlias 'gitlab.com' `
    -HostName 'gitlab.com'
```

Idempotent:

| Step | Skip condition |
|---|---|
| `ssh-keygen` | `~/.ssh/<KeyAlias>` already exists |
| `~/.ssh/config` entry | A `Host <HostAlias>` block is already there |
| Clipboard + browser open | Always runs (useful if the key isn't on GitHub yet) |

The script does NOT touch git itself — no install, no gitconfig, no identity. Run `Setup-Git.ps1` for those, or invoke `git config` directly.

## Multi-account workflow

After both scripts have run (one Setup-Git, one or more New-GitHubSshProfile), `~/.ssh/config` looks like:

```
Host github.com
    HostName github.com
    User git
    IdentityFile C:\Users\you\.ssh\id_ed25519_personal
    IdentitiesOnly yes

Host github.com-work
    HostName github.com
    User git
    IdentityFile C:\Users\you\.ssh\id_ed25519_work
    IdentitiesOnly yes
```

Clone a work repo by replacing the host in the URL:

```bash
# Original (uses primary account):
git clone git@github.com:work-org/repo.git

# Work alias (uses id_ed25519_work):
git clone git@github.com-work:work-org/repo.git
```

For per-repo identity overrides (e.g. all repos under `~/work/` use work email automatically), add `includeIf` to your global config:

```
[includeIf "gitdir:~/work/"]
    path = ~/.gitconfig-work
```

`~/.gitconfig-work` then contains the work `[user]` block. This is NOT in the repo's `profiles/git/.gitconfig` because the path varies per machine — but you can edit `~/.gitconfig` directly (it survives subsequent `Install-Profiles` runs since identity preservation works at the section level, and `includeIf` blocks are preserved too… actually, no — only `user.name` and `user.email` are explicitly preserved; if you add other identity-related sections you may want to put them in `profiles/git/.gitconfig` instead so they're version-controlled).

## Why an in-repo `.gitconfig`?

The repo holds `profiles/git/.gitconfig` — the actual global config. Originally this was a public Gist, which meant maintaining two sources of truth. Bringing it in-repo:

- Single source of truth, versioned with everything else.
- No network dependency once you've cloned.
- File is identity-free (no `[user] name=…` block). Identity is set via `git config --global` and preserved across redeploys.

Future Linux split: add `profiles/git/.gitconfig.windows` + `profiles/git/.gitconfig.linux`, branch by `$IsWindows`/`$IsLinux` in the deploy logic. Not built today; current `.gitconfig` covers both OSes.

## SSH key passphrase

`New-GitHubSshProfile.ps1` generates ed25519 keys with **empty passphrase** (`-N '""'`). Tradeoff:

- **Pro**: No prompts during `git push` / `git fetch`. Smooth CLI experience.
- **Con**: If your `~/.ssh/` is exfiltrated, the keys are directly usable.

If you want passphrases, edit the script to drop `-N '""'`. The OpenSSH agent (`ssh-agent` service on Windows) caches unlocked keys for the session.

## Verifying

After Setup-Git + New-GitHubSshProfile have run:

```powershell
git config --global --list      # should show user.name, user.email, plus everything from profiles/git/.gitconfig
ssh -T git@github.com           # "Hi <username>! You've successfully authenticated..."
ssh -T git@github.com-work      # only if you set up a -work host alias
```

If `ssh -T` fails:

- **Permission denied (publickey)**: GitHub doesn't have the public key yet. Re-open `https://github.com/settings/ssh` and paste from `~/.ssh/<KeyAlias>.pub` (`Get-Content ~/.ssh/id_ed25519_personal.pub | Set-Clipboard`).
- **Could not resolve hostname**: typo in the host alias, or `~/.ssh/config` has a syntax error. `ssh -G github.com` shows what config the client is reading.

## The bootstrap touch-point

`bootstrap.ps1` step `80-profiles` calls `Install-Profiles.ps1 -NoInit` which deploys the gitconfig with **identity preservation**. So after a fresh bootstrap your `~/.gitconfig` matches the repo's content + retains identity (if any was set beforehand).

If you've never set identity, bootstrap's run completes but `git commit` will then fail until you set it. Either run `Setup-Git.ps1` (prompts for name/email) or set directly:

```powershell
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```
