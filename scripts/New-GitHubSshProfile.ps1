<#
.SYNOPSIS
    Add a new GitHub SSH profile: generate an ed25519 key, append a Host
    block to ~/.ssh/config, copy the public key to the clipboard, and open
    https://github.com/settings/ssh/new in your browser.

.DESCRIPTION
    Reusable per GitHub account. Pick a distinct KeyAlias + HostAlias for
    each: e.g. KeyAlias=id_ed25519_personal + HostAlias=github.com for
    your main account; KeyAlias=id_ed25519_work + HostAlias=github.com-work
    for a second.

    Fully idempotent:
      - Skips key generation if ~/.ssh/<KeyAlias> already exists.
      - Skips the ~/.ssh/config entry if a `Host <HostAlias>` block is
        already present.
      - The clipboard + browser step always runs so you can re-register
        if the key isn't on GitHub yet.

    No git install, no gitconfig deployment, no identity setting — those
    are handled by Setup-Git.ps1.

.PARAMETER Email
    Email used in the SSH key comment (-C arg to ssh-keygen). Cosmetic;
    helps identify the key on GitHub.

.PARAMETER KeyAlias
    SSH key filename (without path). Default: id_ed25519_github.
    Examples: id_ed25519_personal, id_ed25519_work, id_ed25519_oss.

.PARAMETER HostAlias
    Host alias for ~/.ssh/config. Default: github.com.
    For multiple accounts, use the URL trick: github.com, github.com-work, etc.
    Clone with: git clone git@<HostAlias>:org/repo.git

.PARAMETER HostName
    Real hostname. Default: github.com.

.PARAMETER User
    SSH user. Default: git.

.EXAMPLE
    .\New-GitHubSshProfile.ps1 -Email me@example.com

.EXAMPLE
    .\New-GitHubSshProfile.ps1 -Email me@work.com -KeyAlias id_ed25519_work -HostAlias github.com-work

.EXAMPLE
    .\New-GitHubSshProfile.ps1 -Email me@gitlab.com -KeyAlias id_ed25519_gitlab -HostAlias gitlab.com -HostName gitlab.com
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Email,
    [string]$KeyAlias = 'id_ed25519_github',
    [string]$HostAlias = 'github.com',
    [string]$HostName = 'github.com',
    [string]$User = 'git'
)

$sshDir     = Join-Path $HOME '.ssh'
$configPath = Join-Path $sshDir 'config'
$keyPath    = Join-Path $sshDir $KeyAlias
$pubKeyPath = "$keyPath.pub"

if (-not (Test-Path $sshDir)) {
    Write-Host "Creating $sshDir ..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
}

if (-not (Test-Path $configPath)) {
    Write-Host "Creating $configPath ..." -ForegroundColor Cyan
    New-Item -ItemType File -Path $configPath -Force | Out-Null
}

# ---- Generate key (idempotent) ---------------------------------------------

if (Test-Path $keyPath) {
    Write-Host "SSH key '$KeyAlias' already exists at $keyPath — skipping generation." -ForegroundColor Yellow
} else {
    Write-Host "Generating ed25519 SSH key: $keyPath" -ForegroundColor Cyan
    & ssh-keygen -t ed25519 -C $Email -f $keyPath -N '""'
    if ($LASTEXITCODE -ne 0) {
        throw "ssh-keygen exited with code $LASTEXITCODE"
    }
}

# ---- ~/.ssh/config entry (idempotent) --------------------------------------

$configContent = Get-Content $configPath -Raw -ErrorAction SilentlyContinue
if ($configContent -and $configContent -match "(?m)^\s*Host\s+$([regex]::Escape($HostAlias))(\s|$)") {
    Write-Host "Host alias '$HostAlias' already in $configPath — skipping config entry." -ForegroundColor Yellow
} else {
    Write-Host "Appending Host '$HostAlias' to $configPath ..." -ForegroundColor Cyan
    $entry = @"

Host $HostAlias
    HostName $HostName
    User $User
    IdentityFile $keyPath
    IdentitiesOnly yes
"@
    Add-Content -Path $configPath -Value $entry
    Write-Host "  added." -ForegroundColor Green
}

# ---- Clipboard + open GitHub (always — useful if key isn't on GitHub yet) --

if (-not (Test-Path $pubKeyPath)) {
    Write-Host "Public key not found at $pubKeyPath — cannot copy to clipboard." -ForegroundColor Red
    return
}

Get-Content $pubKeyPath | Set-Clipboard
Write-Host ""
Write-Host "Public key copied to clipboard:" -ForegroundColor Green
Write-Host "  $pubKeyPath" -ForegroundColor DarkGray
Write-Host ""

if ($HostName -match 'github') {
    Write-Host "Opening https://github.com/settings/ssh/new ..." -ForegroundColor Cyan
    Start-Process 'https://github.com/settings/ssh/new'
    Write-Host "Paste the key (Ctrl+V) into the 'Key' field, give it a title, and save." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Verify with:  ssh -T git@$HostAlias" -ForegroundColor DarkGray
} else {
    Write-Host "Paste the key into your SSH-keys page for $HostName." -ForegroundColor Yellow
}
