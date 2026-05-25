# =============================================================================
# 70 — Optional Windows features + WSL2
#
# Features: Hyper-V, VMP, WSL, Sandbox.
# WSL: kernel update, install Ubuntu if missing, write .wslconfig.
#
# .wslconfig is conservative by default — never overwrites existing user-edited
# files unless -ForceWslConfig is set by bootstrap.
#
# Tags: features (features); wsl (WSL); wsl,config (.wslconfig)
# =============================================================================

if (-not $script:LogStamp) { $script:LogStamp = Get-Date -Format 'yyyyMMdd-HHmmss' }

Invoke-Step -Name "Windows features: Hyper-V, WSL, VMP, Sandbox" -Tags @('features') -ContinueOnError -SkipOnDryRun -Action {
    $features = @(
        'Microsoft-Hyper-V-All',
        'VirtualMachinePlatform',
        'Microsoft-Windows-Subsystem-Linux',
        'Containers-DisposableClientVM'
    )
    foreach ($f in $features) {
        try {
            $state = (Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction Stop).State
            if ($state -eq 'Enabled') {
                Write-Log -Level DEBUG -Message "  = $f (already enabled)"
            } else {
                Enable-WindowsOptionalFeature -Online -FeatureName $f -All -NoRestart -ErrorAction Stop | Out-Null
                Write-Log -Level DEBUG -Message "  + $f (enabled)"
            }
        } catch {
            Write-Log -Level WARN -Message "  ! $f failed: $($_.Exception.Message)"
        }
    }
}

Invoke-Step -Name "WSL: update kernel" -Tags @('wsl') -ContinueOnError -SkipOnDryRun -Action {
    wsl --update
}

Invoke-Step -Name "WSL: install Ubuntu (if missing)" -Tags @('wsl') -ContinueOnError -SkipOnDryRun -Action {
    $listed = (wsl --list --quiet 2>$null) -join "`n"
    $listed = $listed -replace "`0", ''
    if ($listed -match 'Ubuntu') {
        Write-Log -Level DEBUG -Message "  Ubuntu distro already registered — not touching it"
    } else {
        wsl --install -d Ubuntu --no-launch
        Write-Log -Level DEBUG -Message "  Ubuntu install initiated (finishes on first launch)"
    }
}

Invoke-Step -Name "WSL: write .wslconfig" -Tags @('wsl','config') -SkipOnDryRun -Action {
    $wslConfig = @'
# Managed by win-setup bootstrap.ps1
[wsl2]
memory=16GB
processors=8
swap=4GB
localhostForwarding=true
nestedVirtualization=true

[experimental]
autoMemoryReclaim=gradual
sparseVhd=true
'@
    $path = Join-Path $env:USERPROFILE '.wslconfig'

    if (-not (Test-Path $path)) {
        Set-Content -Path $path -Value $wslConfig -Encoding ASCII -Force
        Write-Log -Level DEBUG -Message "  Wrote $path (file did not exist)"
        return
    }

    $existing = Get-Content $path -Raw -ErrorAction SilentlyContinue
    if ($existing -eq $wslConfig) {
        Write-Log -Level DEBUG -Message "  $path already matches canonical config — no change"
        return
    }

    if (-not $ForceWslConfig) {
        Write-Log -Level WARN -Message "  $path exists and differs from canonical config."
        Write-Log -Level WARN -Message "  Leaving it alone. Pass -ForceWslConfig to overwrite (with backup)."
        return
    }

    $backup = "$path.bak-$($script:LogStamp)"
    Copy-Item $path $backup -Force
    Set-Content -Path $path -Value $wslConfig -Encoding ASCII -Force
    Write-Log -Level WARN -Message "  Overwrote $path (backup: $backup)"
}
