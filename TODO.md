# TODO

## Split Claude Code config into a separate dotfiles repo

Claude Code config (`~/.claude/CLAUDE.md`, `settings.json`, hooks, agents, commands, skills) currently lives outside this repo and is not bootstrapped onto fresh machines.

**Decision:** keep it OUT of `windows-system-config`. Reasons:

- This repo is Windows-only by charter; Claude Code config is cross-platform (same files for WSL / Linux / macOS).
- Churn rates don't match — Windows base settles for months, Claude Code config (skills, hooks, agent prompts) iterates weekly. Mixing the two muddies `git log` for both.
- Obsidian is the wrong tool for syncing dotfiles (markdown KB, not a deployer); fine for *notes about* the setup, not the files themselves.

**Shape of the work:**

1. Stand up a small `claude-config` repo: mirror of `~/.claude/` plus a `Deploy-ClaudeConfig.ps1` (Windows) and a `deploy-claude-config.sh` (POSIX) that copy/symlink into `~/.claude/`. Identity-free; mirror the `Setup-Git.ps1` pattern of preserving local additions on redeploy.
2. Decide on backup behavior (`.bak-<stamp>`, same convention as `Install-Profiles.ps1`).
3. Add `steps/90-claude-config.ps1` here (tag: `claude`) that clones-or-pulls the `claude-config` repo into a known location (e.g. `~/code/claude-config`) and runs its deploy script with `-NoInit` so output lands in the bootstrap summary.
4. Update `docs/install-checklist.md` § 15 to drop manual Claude Code config steps (if any) and point at the new step.
5. Update `CLAUDE.md` and `README.md` tag tables for the new `claude` tag.

**Open questions to resolve before starting:**

- Does the `claude-config` repo include personal prompts / project memory, or only structural config (hooks, settings.json, commands)? If the former, it's a private repo — adjust the clone step to use the SSH host alias from `~/.ssh/config`.
- Hash-sentinel mechanic like `61-app-extras`, or unconditional redeploy each bootstrap run? Lean unconditional — the deploy is cheap and the files change often.
