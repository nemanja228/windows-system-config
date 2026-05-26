# Post-install hook for Microsoft.VisualStudioCode — runs after winget installs
# VS Code (via the apps step). Installs a curated extension set covering the
# languages this repo targets as "general-purpose, but I do real dev in Rider".
#
# Idempotent: `code --install-extension` is a no-op if the extension is already
# at the right version. Safe to re-run.
#
# TypeScript intentionally not in the list — VS Code ships built-in TS language
# services, and ESLint + Prettier (in the list) cover linting and formatting.

Write-Host "`n--- VS Code: installing extensions ---" -ForegroundColor Cyan

# Refresh PATH so `code` is found if VS Code was just installed in this session.
$env:PATH = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')

$codeCmd = Get-Command code -ErrorAction SilentlyContinue
if (-not $codeCmd) {
    Write-Host "  code CLI not on PATH — is VS Code installed? Skipping extension install." -ForegroundColor Yellow
    return
}

Write-Host "  Using code at: $($codeCmd.Source)" -ForegroundColor DarkGray

$extensions = @(
    # Languages
    'ms-python.python',                # Python language services
    'ms-vscode.powershell',            # PowerShell language services + debugger
    'ms-dotnettools.csharp',           # C# language services (basic; not the full Dev Kit)
    'mads-hartmann.bash-ide-vscode',   # Bash language services
    'redhat.vscode-xml',               # XML language services + schema validation
    'redhat.vscode-yaml',              # YAML language services + schema support
    'yzhang.markdown-all-in-one',      # Markdown: TOC, shortcuts, list editing

    # Editor ergonomics
    'esbenp.prettier-vscode',          # HTML/CSS/JS/TS formatter
    'dbaeumer.vscode-eslint',          # JS/TS linting
    'editorconfig.editorconfig',       # Respect .editorconfig project conventions

    # Git
    'eamodio.gitlens'                  # Inline git blame, history, etc.
)

$installed = 0
$skipped   = 0
$failed    = 0

foreach ($ext in $extensions) {
    Write-Host "  + $ext" -ForegroundColor DarkGray
    $output = & code --install-extension $ext --force 2>&1
    if ($LASTEXITCODE -eq 0) {
        if ($output -match 'already installed') { $skipped++ } else { $installed++ }
    } else {
        Write-Host "    ! failed: $output" -ForegroundColor Yellow
        $failed++
    }
}

Write-Host "`n  Summary: $installed installed, $skipped already present, $failed failed" -ForegroundColor Green

# Defender exclusion for the VS Code user data dir (extension installs and
# JS/TS language services hammer this; Defender real-time scans add latency).
Add-DefenderExclusion -Path "$env:USERPROFILE\.vscode" -Source 'vscode'
