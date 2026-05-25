<#
.SYNOPSIS
    Deploy profile files from the repo into their real OS locations.

.DESCRIPTION
    Six categories handled, each as one Invoke-Step so the run shows a summary:

      git         profiles/git/.gitconfig
                    -> $HOME\.gitconfig

      pwsh        profiles/powershell/Microsoft.PowerShell_profile.ps1
                    -> $PROFILE.CurrentUserAllHosts

      omp         profiles/oh-my-posh/*.omp.json
                    -> $env:LocalAppData\oh-my-posh\themes\

      wt          profiles/windows-terminal/settings.json
                    -> $env:LocalAppData\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json

      fonts       profiles/fonts/*.ttf, *.otf
                    -> %WINDIR%\Fonts\ + HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts
                    (install-only, never symlinked; requires elevation)

      ahk         profiles/autohotkey/WtTransparent.ahk
                    -> shortcut in %APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\
                    (.ahk stays in the repo; shortcut points at it)

    All targets are backed up to .bak-<stamp> before being overwritten, unless -Force.
    -WhatIf shows planned operations without writing anything.
    -Symlink creates symbolic links instead of copies — requires elevation OR
    Developer Mode. Falls back to copy with a WARN if neither.

    Fonts are always installed via Copy (not symlinked) because the Fonts
    namespace COM API needs a real file.

.PARAMETER Symlink
    Use symbolic links instead of copies for the file-based targets. Requires
    elevation OR Developer Mode on Windows.

.PARAMETER WhatIf
    Show what would happen without changing anything.

.PARAMETER Force
    Skip the backup of existing target files (overwrites directly).

.PARAMETER Only
    Install just specified categories. Default: all six.
    Choices: git, pwsh, omp, wt, fonts, ahk

.EXAMPLE
    .\Install-Profiles.ps1
    # Deploy everything, copies, backup existing

.EXAMPLE
    .\Install-Profiles.ps1 -Symlink
    # Symlinks where possible (needs elevation or Dev Mode)

.EXAMPLE
    .\Install-Profiles.ps1 -Only git,pwsh
    # Just git config + PowerShell profile

.EXAMPLE
    .\Install-Profiles.ps1 -WhatIf
    # Preview only
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Symlink,
    [switch]$Force,

    [ValidateSet('git','pwsh','omp','wt','fonts','ahk')]
    [string[]]$Only,

    # When set, skip own Initialize-Logging + Show-Summary so this script can
    # share the calling session's logger (e.g. when invoked from bootstrap's
    # steps/80-profiles.ps1). Inner Invoke-Step calls still write to the
    # module's shared $script:Summary, so categories show up in the caller's
    # summary table.
    [switch]$NoInit
)

# =============================================================================
# Module
# =============================================================================

$scriptDir = $PSScriptRoot
$repoRoot  = Split-Path -Parent $scriptDir
$modulePath = Join-Path $repoRoot 'lib\WinSetup'

# When -NoInit is set, a parent session (e.g. bootstrap.ps1) has already loaded
# the module and populated its $script:Summary / $script:LogDryRun. Re-importing
# with -Force would reset those and break the integration. So: import without
# -Force when the module is already loaded.
if (Get-Module -Name WinSetup) {
    Import-Module $modulePath -ErrorAction SilentlyContinue
} else {
    Import-Module $modulePath -Force
}

if (-not $NoInit) {
    $init = Initialize-Logging -LogPrefix 'install-profiles'
    $script:LogDir   = $init.LogDir
    $script:LogStamp = $init.Stamp

    Write-Log -Level STEP -Message "==============================================="
    Write-Log -Level STEP -Message " win-setup Install-Profiles"
    Write-Log -Level STEP -Message "==============================================="
    Write-Log -Level INFO -Message "Repo:   $repoRoot"
    Write-Log -Level INFO -Message "Mode:   $(if ($Symlink) { 'Symlink' } else { 'Copy' })"
    Write-Log -Level INFO -Message "Force:  $($Force.IsPresent)"
    Write-Log -Level INFO -Message "WhatIf: $($WhatIfPreference)"
    if ($Only) { Write-Log -Level INFO -Message "Only:   $($Only -join ',')" }
}

# =============================================================================
# Helpers
# =============================================================================

function Test-DevMode {
    try {
        $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
        if (-not (Test-Path $key)) { return $false }
        (Get-ItemProperty -Path $key -Name 'AllowDevelopmentWithoutDevLicense' -ErrorAction Stop).AllowDevelopmentWithoutDevLicense -eq 1
    } catch { $false }
}

function Test-IsAdmin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Copy-OrLink {
    param(
        [Parameter(Mandatory=$true)][string]$Source,
        [Parameter(Mandatory=$true)][string]$Target,
        [switch]$Symlink,
        [switch]$Force
    )
    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Source does not exist: $Source"
    }

    # Ensure parent dir
    $parent = Split-Path -Parent $Target
    if (-not (Test-Path -LiteralPath $parent)) {
        if ($PSCmdlet.ShouldProcess($parent, "Create directory")) {
            New-Item -Path $parent -ItemType Directory -Force | Out-Null
        }
    }

    # Backup if target exists
    if ((Test-Path -LiteralPath $Target) -and -not $Force) {
        $backup = "$Target.bak-$script:LogStamp"
        if ($PSCmdlet.ShouldProcess($Target, "Backup to $backup")) {
            Copy-Item -LiteralPath $Target -Destination $backup -Force
            Write-Log -Level DEBUG -Message "    backup: $backup"
        }
    }

    # Existing item must be removed before mklink or before clean copy
    if (Test-Path -LiteralPath $Target) {
        if ($PSCmdlet.ShouldProcess($Target, "Remove existing")) {
            Remove-Item -LiteralPath $Target -Force
        }
    }

    if ($Symlink) {
        $canSymlink = (Test-IsAdmin) -or (Test-DevMode)
        if (-not $canSymlink) {
            Write-Log -Level WARN -Message "    -Symlink requested but neither elevated nor Dev Mode; falling back to copy"
            if ($PSCmdlet.ShouldProcess($Target, "Copy from $Source")) {
                Copy-Item -LiteralPath $Source -Destination $Target -Force
            }
            return
        }
        if ($PSCmdlet.ShouldProcess($Target, "Symlink to $Source")) {
            New-Item -ItemType SymbolicLink -Path $Target -Target $Source -Force | Out-Null
            Write-Log -Level DEBUG -Message "    symlink: $Target -> $Source"
        }
    } else {
        if ($PSCmdlet.ShouldProcess($Target, "Copy from $Source")) {
            Copy-Item -LiteralPath $Source -Destination $Target -Force
            Write-Log -Level DEBUG -Message "    copy: $Source -> $Target"
        }
    }
}

function Install-Font {
    param([Parameter(Mandatory=$true)][string]$FontFile)
    $fontsDir = Join-Path $env:WinDir 'Fonts'
    $name = Split-Path -Leaf $FontFile
    $target = Join-Path $fontsDir $name

    if (Test-Path -LiteralPath $target) {
        Write-Log -Level DEBUG -Message "    font already present: $name (skip)"
        return
    }

    if (-not (Test-IsAdmin)) {
        throw "Installing fonts requires elevation. Re-run from elevated PowerShell."
    }

    if ($PSCmdlet.ShouldProcess($name, "Install to $fontsDir")) {
        # Shell.Application COM with namespace(0x14) (FONTS) + CopyHere flag 0x10 (no UI)
        # is the documented way to install a font without restart — it copies the file
        # AND registers it in HKLM\...\Fonts in one operation.
        $shell = New-Object -ComObject Shell.Application
        $fonts = $shell.NameSpace(0x14)
        $fonts.CopyHere($FontFile, 0x10)
        Write-Log -Level DEBUG -Message "    installed font: $name"
    }
}

function New-StartupShortcut {
    param(
        [Parameter(Mandatory=$true)][string]$Target,
        [Parameter(Mandatory=$true)][string]$ShortcutName
    )
    $startup = [Environment]::GetFolderPath('Startup')
    $linkPath = Join-Path $startup "$ShortcutName.lnk"

    if (Test-Path -LiteralPath $linkPath) {
        # Check if it already points at the right target
        $wsh = New-Object -ComObject WScript.Shell
        $existing = $wsh.CreateShortcut($linkPath)
        if ($existing.TargetPath -eq $Target) {
            Write-Log -Level DEBUG -Message "    startup shortcut already points at $Target — skip"
            return
        }
        Write-Log -Level INFO -Message "    existing shortcut at $linkPath points elsewhere; overwriting"
    }

    if ($PSCmdlet.ShouldProcess($linkPath, "Create startup shortcut to $Target")) {
        $wsh = New-Object -ComObject WScript.Shell
        $shortcut = $wsh.CreateShortcut($linkPath)
        $shortcut.TargetPath = $Target
        $shortcut.WorkingDirectory = Split-Path -Parent $Target
        $shortcut.Save()
        Write-Log -Level DEBUG -Message "    shortcut: $linkPath -> $Target"
    }
}

# =============================================================================
# Categories
# =============================================================================

function Should-Install { param([string]$Cat) -not $Only -or ($Only -contains $Cat) }

# --- git ---

if (Should-Install 'git') {
    Invoke-Step -Name "git: deploy .gitconfig (identity preserved)" -Tags @('profiles','git') -ContinueOnError -SkipOnDryRun -Action {
        $src = Join-Path $repoRoot 'profiles\git\.gitconfig'
        $dst = Join-Path $HOME '.gitconfig'

        # Snapshot identity via git itself (reads from current ~/.gitconfig).
        # If git isn't installed yet, there's nothing to preserve.
        $existingName  = ''
        $existingEmail = ''
        if (Get-Command git -ErrorAction SilentlyContinue) {
            $existingName  = (& git config --global --get user.name  2>$null) -join ''
            $existingEmail = (& git config --global --get user.email 2>$null) -join ''
        } else {
            Write-Log -Level DEBUG -Message "    git not on PATH yet — no identity to preserve"
        }

        # Force copy (never symlink) for .gitconfig. The repo file is identity-
        # free by design; a symlink would route `git config --global` writes
        # INTO the repo file, leaking personal identity into a shared file.
        Copy-OrLink -Source $src -Target $dst -Force:$Force

        if ($existingName) {
            if ($PSCmdlet.ShouldProcess("user.name", "git config --global = $existingName")) {
                & git config --global user.name $existingName | Out-Null
                Write-Log -Level DEBUG -Message "    restored user.name  = $existingName"
            }
        }
        if ($existingEmail) {
            if ($PSCmdlet.ShouldProcess("user.email", "git config --global = $existingEmail")) {
                & git config --global user.email $existingEmail | Out-Null
                Write-Log -Level DEBUG -Message "    restored user.email = $existingEmail"
            }
        }
    }
}

# --- pwsh ---

if (Should-Install 'pwsh') {
    Invoke-Step -Name "pwsh: deploy `$PROFILE.CurrentUserAllHosts" -Tags @('profiles','pwsh') -ContinueOnError -SkipOnDryRun -Action {
        $src = Join-Path $repoRoot 'profiles\powershell\Microsoft.PowerShell_profile.ps1'
        $dst = $PROFILE.CurrentUserAllHosts
        if (-not $dst) {
            # If running under powershell.exe without an established $PROFILE.CurrentUserAllHosts,
            # synthesize the standard path.
            $dst = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\profile.ps1'
        }
        Copy-OrLink -Source $src -Target $dst -Symlink:$Symlink -Force:$Force
    }
}

# --- omp ---

if (Should-Install 'omp') {
    Invoke-Step -Name "omp: deploy themes" -Tags @('profiles','omp') -ContinueOnError -SkipOnDryRun -Action {
        $srcDir = Join-Path $repoRoot 'profiles\oh-my-posh'
        $dstDir = Join-Path $env:LocalAppData 'oh-my-posh\themes'
        $themes = Get-ChildItem -Path $srcDir -Filter '*.omp.json' -File
        if (-not $themes -or $themes.Count -eq 0) {
            Write-Log -Level WARN -Message "  no themes in $srcDir"
            return
        }
        foreach ($theme in $themes) {
            $dst = Join-Path $dstDir $theme.Name
            Copy-OrLink -Source $theme.FullName -Target $dst -Symlink:$Symlink -Force:$Force
        }
    }
}

# --- wt ---

if (Should-Install 'wt') {
    Invoke-Step -Name "wt: deploy settings.json" -Tags @('profiles','wt') -ContinueOnError -SkipOnDryRun -Action {
        $src = Join-Path $repoRoot 'profiles\windows-terminal\settings.json'
        $dst = Join-Path $env:LocalAppData 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
        if (-not (Test-Path (Split-Path -Parent $dst))) {
            Write-Log -Level WARN -Message "  Windows Terminal LocalState dir not found — is WT installed? Skipping."
            return
        }
        Copy-OrLink -Source $src -Target $dst -Symlink:$Symlink -Force:$Force
    }
}

# --- fonts ---

if (Should-Install 'fonts') {
    Invoke-Step -Name "fonts: install Nerd Fonts" -Tags @('profiles','fonts') -ContinueOnError -SkipOnDryRun -Action {
        $srcDir = Join-Path $repoRoot 'profiles\fonts'
        if (-not (Test-Path $srcDir)) {
            Write-Log -Level WARN -Message "  profiles\fonts\ does not exist — skipping"
            return
        }
        $fonts = Get-ChildItem -Path $srcDir -Include '*.ttf','*.otf' -File -Recurse
        if (-not $fonts -or $fonts.Count -eq 0) {
            Write-Log -Level WARN -Message "  no .ttf/.otf in $srcDir — skipping"
            return
        }
        foreach ($font in $fonts) {
            Install-Font -FontFile $font.FullName
        }
    }
}

# --- ahk ---

if (Should-Install 'ahk') {
    Invoke-Step -Name "ahk: startup shortcut for WtTransparent.ahk" -Tags @('profiles','ahk') -ContinueOnError -SkipOnDryRun -Action {
        $src = Join-Path $repoRoot 'profiles\autohotkey\WtTransparent.ahk'
        if (-not (Test-Path -LiteralPath $src)) {
            Write-Log -Level WARN -Message "  $src not found — skipping"
            return
        }
        New-StartupShortcut -Target $src -ShortcutName 'WtTransparent'
    }
}

# =============================================================================
# Wrap up — only when standalone (bootstrap's dispatcher handles its own).
# =============================================================================

if (-not $NoInit) {
    Show-Summary

    $failed = (Get-StepSummary | Where-Object { -not $_.Success }).Count
    if ($failed -eq 0) {
        Write-Log -Level SUCCESS -Message "Install-Profiles complete."
        exit 0
    } else {
        Write-Log -Level WARN -Message "$failed step(s) failed."
        exit 1
    }
}
