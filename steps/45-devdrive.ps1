# =============================================================================
# 45 — Dev Drive: redirect package-manager caches to the ReFS Dev Drive
#
# Microsoft's Dev Drive (Win11 22H2+) is ReFS + Defender Performance Mode.
# Redirecting package caches there yields meaningful throughput wins on
# package-heavy workflows (npm install, dotnet restore, cargo build).
#
# What this step does:
#   1. Auto-detects the Dev Drive via `Get-Volume` (ReFS + Fixed) +
#      `fsutil devdrv query` — does NOT assume any specific drive letter.
#   2. Creates <DevDrive>:\dev\packages\{nuget,npm,yarn,cargo,...}
#   3. Sets per-tool env vars at User scope (idempotent — skips if already
#      pointing at the right place, WARNs + overrides if pointing elsewhere).
#
# What it does NOT do:
#   - Create a Dev Drive if none exists (that needs unallocated space + UI
#     interaction; see Settings → System → Storage → Disks & volumes).
#   - Migrate existing caches from C:\. The old caches are abandoned; tools
#     rebuild them on next use. Delete the old dirs manually to reclaim space:
#       %UserProfile%\.nuget\packages
#       %AppData%\npm-cache
#       %LocalAppData%\Yarn\Cache
#       %UserProfile%\.cargo
#       %LocalAppData%\pip\Cache
#       %UserProfile%\.gradle
#       %LocalAppData%\vcpkg\archives
#   - Touch source trees. Move your source manually to <DevDrive>:\dev\source
#     (defender exclusions still cover C:\Users\…\source by default).
#
# Env vars take effect in NEW shells. Current bootstrap session does NOT
# pick them up — that's fine, package installs happen via winget not via
# the affected tools during bootstrap.
#
# Locale note: Dev Drive detection matches the en-US fsutil output string
# 'trusted developer volume'. On non-English Windows installs `fsutil devdrv
# query` returns a localized phrase and detection silently misses — the step
# becomes a no-op. Acceptable for this repo's en-US-UI premise; fork
# considerations would require a non-string-matching probe (e.g. parsing
# `Get-Volume`'s `DevDrive` property once it ships, or P/Invoke on
# GetVolumeInformationW for FILE_VOLUME_DEV_VOLUME).
# =============================================================================

function script:Get-DevDriveVolume {
    [CmdletBinding()]
    param()

    $candidates = Get-Volume | Where-Object {
        $_.DriveLetter -and
        $_.FileSystemType -eq 'ReFS' -and
        $_.DriveType -eq 'Fixed'
    }
    if (-not $candidates) { return $null }

    $found = @()
    foreach ($vol in $candidates) {
        $letter = "$($vol.DriveLetter):"
        $output = & fsutil devdrv query $letter 2>&1 | Out-String
        # fsutil emits "trusted developer volume" (en-US) on confirmed Dev Drives.
        # When run non-elevated it returns "Access is denied" instead — caller
        # must be admin (bootstrap is, ad-hoc invocation needs elevation).
        if ($output -match 'trusted developer volume') {
            $found += [PSCustomObject]@{
                Letter = $vol.DriveLetter
                Root   = "$($vol.DriveLetter):\"
                SizeGB = [math]::Round($vol.Size / 1GB, 1)
                FreeGB = [math]::Round($vol.SizeRemaining / 1GB, 1)
            }
        }
    }
    if ($found.Count -eq 0) { return $null }
    if ($found.Count -gt 1) {
        Write-Log -Level WARN -Message "  Multiple Dev Drives detected ($($found.Letter -join ', ')); using first: $($found[0].Letter):"
    }
    return $found[0]
}

Invoke-Step -Name "Dev Drive: detect + redirect package caches" -Tags @('devdrive') -ContinueOnError -SkipOnDryRun -Action {
    $dev = Get-DevDriveVolume
    if (-not $dev) {
        Write-Log -Level INFO -Message "  No Dev Drive detected. Skip."
        Write-Log -Level INFO -Message "  To set one up: Settings -> System -> Storage -> Disks & volumes -> Create Dev Drive"
        return
    }
    Write-Log -Level DEBUG -Message "  Found Dev Drive: $($dev.Root) ($($dev.FreeGB) GB free of $($dev.SizeGB) GB)"

    $base = Join-Path $dev.Root 'dev\packages'

    # Tool descriptors. EnvVar is the user-scope environment variable each
    # tool reads to relocate its cache. SubDir lives under <DevDrive>\dev\packages\.
    $tools = @(
        [pscustomobject]@{ Tool = 'NuGet';  EnvVar = 'NUGET_PACKAGES';            SubDir = 'nuget'  }
        [pscustomobject]@{ Tool = 'npm';    EnvVar = 'npm_config_cache';          SubDir = 'npm'    }
        [pscustomobject]@{ Tool = 'yarn';   EnvVar = 'YARN_CACHE_FOLDER';         SubDir = 'yarn'   }
        [pscustomobject]@{ Tool = 'Cargo';  EnvVar = 'CARGO_HOME';                SubDir = 'cargo'  }
        [pscustomobject]@{ Tool = 'pip';    EnvVar = 'PIP_CACHE_DIR';             SubDir = 'pip'    }
        [pscustomobject]@{ Tool = 'Gradle'; EnvVar = 'GRADLE_USER_HOME';          SubDir = 'gradle' }
        [pscustomobject]@{ Tool = 'Vcpkg';  EnvVar = 'VCPKG_DEFAULT_BINARY_CACHE'; SubDir = 'vcpkg'  }
        [pscustomobject]@{ Tool = 'Go';     EnvVar = 'GOMODCACHE';                SubDir = 'go-mod' }
    )

    $newCount = 0
    $skipCount = 0
    foreach ($t in $tools) {
        $path = Join-Path $base $t.SubDir
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
            Write-Log -Level DEBUG -Message "  + dir $path"
        }

        $current = [Environment]::GetEnvironmentVariable($t.EnvVar, 'User')
        if ($current -eq $path) {
            Write-Log -Level DEBUG -Message "  = $($t.Tool) already at $path (skip)"
            $skipCount++
            continue
        }
        if ($current) {
            Write-Log -Level WARN -Message "  ~ $($t.Tool): $($t.EnvVar)='$current' -> overriding to $path"
        }
        [Environment]::SetEnvironmentVariable($t.EnvVar, $path, 'User')
        Write-Log -Level DEBUG -Message "  + $($t.Tool) -> $path  (User env: $($t.EnvVar))"
        $newCount++
    }

    Write-Log -Level INFO -Message "  $newCount tool(s) (re)pointed; $skipCount already correct"
    Write-Log -Level INFO -Message "  Env vars apply to NEW shells only — current session unaffected."
    Write-Log -Level INFO -Message "  Old caches on C: are abandoned; delete manually to reclaim space."
}
