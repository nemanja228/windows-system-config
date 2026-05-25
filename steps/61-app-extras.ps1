# =============================================================================
# 61 — App extras: scan post-install/*.ps1 and run hooks for installed apps
#
# Convention: post-install/<winget-package-id>.ps1
# Example:    post-install/Notepad++.Notepad++.ps1
#             post-install/Microsoft.VisualStudioCode.ps1
#
# For each hook script:
#   1. Strip .ps1 to derive the winget package id.
#   2. winget list --id <id> --exact — skip if not installed.
#   3. SHA-256 the script content; compare against sentinel at
#      %LocalAppData%\win-setup\post-install\<id>.hash
#   4. If hash differs (or sentinel missing), run the script with Invoke-Step
#      and write the new hash on success.
#   5. Otherwise skip with a DEBUG log line.
#
# $ForceAppExtras (bootstrap-scope switch) clears all sentinels first, forcing
# every hook to re-run.
#
# Each hook script must remain internally idempotent. The hash sentinel is a
# perf optimization, not a correctness guarantee.
#
# Tags: apps, extras
# =============================================================================

$postInstallDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'post-install'
$sentinelDir    = Join-Path $env:LocalAppData 'win-setup\post-install'

if (-not (Test-Path $sentinelDir)) {
    New-Item -Path $sentinelDir -ItemType Directory -Force | Out-Null
}

if ($ForceAppExtras) {
    Write-Log -Level WARN -Message "  -ForceAppExtras: clearing sentinels in $sentinelDir"
    Get-ChildItem -Path $sentinelDir -Filter '*.hash' -ErrorAction SilentlyContinue | Remove-Item -Force
}

Invoke-Step -Name "Scan post-install/ for app extras" -Tags @('apps','extras') -ContinueOnError -SkipOnDryRun -Action {
    if (-not (Test-Path $postInstallDir)) {
        Write-Log -Level WARN -Message "  $postInstallDir not found — no app extras to run"
        return
    }

    $scripts = Get-ChildItem -Path $postInstallDir -Filter '*.ps1' -File -ErrorAction SilentlyContinue
    if (-not $scripts -or $scripts.Count -eq 0) {
        Write-Log -Level DEBUG -Message "  No post-install scripts found"
        return
    }

    Write-Log -Level INFO -Message "  Found $($scripts.Count) post-install script(s)"

    foreach ($scriptFile in $scripts) {
        $packageId = $scriptFile.BaseName
        Write-Log -Level DEBUG -Message "  -- checking $packageId"

        # Is the app installed?
        $listOutput = & winget list --id $packageId --exact --accept-source-agreements 2>&1
        $installed  = ($LASTEXITCODE -eq 0) -and ($listOutput -join "`n") -match [regex]::Escape($packageId)

        if (-not $installed) {
            Write-Log -Level DEBUG -Message "     not installed — skipping"
            continue
        }

        # Hash check
        $content      = Get-Content -Path $scriptFile.FullName -Raw
        $sha          = (Get-FileHash -InputStream ([System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($content))) -Algorithm SHA256).Hash
        $sentinelFile = Join-Path $sentinelDir ("{0}.hash" -f $packageId)
        $existingSha  = if (Test-Path $sentinelFile) { (Get-Content -Path $sentinelFile -Raw -ErrorAction SilentlyContinue).Trim() } else { $null }

        if ($existingSha -eq $sha) {
            Write-Log -Level DEBUG -Message "     hash matches sentinel — skipping (use -ForceAppExtras to re-run)"
            continue
        }

        # Run inside an Invoke-Step so summary tracks it
        Invoke-Step -Name "Post-install: $packageId" -Tags @('apps','extras') -ContinueOnError -SkipOnDryRun -Action {
            & $scriptFile.FullName
            if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
                throw "Post-install script exited with code $LASTEXITCODE"
            }
        }

        # Only write sentinel if the inner step succeeded
        $summary    = Get-StepSummary
        $lastResult = $summary[$summary.Count - 1]
        if ($lastResult.Success -and -not $lastResult.Skipped) {
            Set-Content -Path $sentinelFile -Value $sha -Encoding ASCII -Force
            Write-Log -Level DEBUG -Message "     sentinel updated: $sentinelFile"
        } else {
            Write-Log -Level WARN -Message "     post-install failed — sentinel NOT updated; will retry next run"
        }
    }
}
