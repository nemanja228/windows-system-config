# =============================================================================
# 20 — Debloat: Win11Debloat + O&O ShutUp10++ + tweaks.reg
#
# Tags: core, debloat (Win11Debloat); + privacy (OOSU10); + config (tweaks.reg)
#
# Bootstrap sets $script:LogDir and $script:LogStamp so per-tool log files share
# the same stamp. If running standalone, these default to %TEMP%\win-setup-logs
# and the current timestamp.
# =============================================================================

if (-not $script:LogDir)   { $script:LogDir   = Join-Path $env:TEMP 'win-setup-logs' }
if (-not $script:LogStamp) { $script:LogStamp = Get-Date -Format 'yyyyMMdd-HHmmss' }

$DebloatLog = Join-Path $script:LogDir "win11debloat-$($script:LogStamp).log"
$OosuLog    = Join-Path $script:LogDir "oosu-$($script:LogStamp).log"
$RegLog     = Join-Path $script:LogDir "reg-import-$($script:LogStamp).log"

Invoke-Step -Name "Win11Debloat (apps + telemetry + UI tweaks)" -Tags @('core','debloat') -ContinueOnError -SkipOnDryRun -Action {
    $customList = Get-ResourcePath -Name 'debloat/CustomAppsList.txt'
    if (Test-Path $customList) {
        Write-Log -Level INFO -Message "  Found custom apps list: $customList"
        $cfgDir = Join-Path $env:TEMP 'Win11Debloat\Config'
        if (-not (Test-Path $cfgDir)) { New-Item -Path $cfgDir -ItemType Directory -Force | Out-Null }
        Copy-Item $customList (Join-Path $cfgDir 'CustomAppsList.txt') -Force
        Write-Log -Level DEBUG -Message "  Copied to $cfgDir\CustomAppsList.txt"
    }

    Start-Transcript -Path $DebloatLog -Append -ErrorAction SilentlyContinue | Out-Null
    try {
        & ([scriptblock]::Create((Invoke-RestMethod -Uri "https://debloat.raphi.re/"))) -RunDefaults -Silent
    } finally {
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
    }
    Write-Log -Level DEBUG -Message "  Win11Debloat transcript: $DebloatLog"
}

Invoke-Step -Name "O&O ShutUp10++ (apply saved privacy config)" -Tags @('core','debloat','privacy') -ContinueOnError -SkipOnDryRun -Action {
    $cfgPath = Get-ResourcePath -Name 'shutup/ooshutup10.cfg'
    if (-not (Test-Path $cfgPath)) {
        Write-Log -Level WARN -Message "  ooshutup10.cfg not found at $cfgPath — skipping."
        Write-Log -Level WARN -Message "  Generate one: download OOSU10.exe interactively, configure, File > Export."
        return
    }
    $oosuExe = Join-Path $env:TEMP 'OOSU10.exe'
    Write-Log -Level DEBUG -Message "  Downloading OOSU10.exe"
    Invoke-WebRequest -Uri 'https://dl5.oo-software.com/files/ooshutup10/OOSU10.exe' -OutFile $oosuExe -UseBasicParsing

    Write-Log -Level DEBUG -Message "  Applying config: $cfgPath"
    $procArgs = @("`"$cfgPath`"", '/quiet')
    $p = Start-Process -FilePath $oosuExe -ArgumentList $procArgs -Wait -PassThru `
            -RedirectStandardOutput $OosuLog -RedirectStandardError "$OosuLog.err" -NoNewWindow
    if ($p.ExitCode -ne 0) {
        throw "OOSU10 exited with code $($p.ExitCode). See $OosuLog"
    }
    Write-Log -Level DEBUG -Message "  OOSU10 exit code: 0"
}

Invoke-Step -Name "Apply registry tweaks (tweaks.reg)" -Tags @('core','debloat','privacy','config') -ContinueOnError -SkipOnDryRun -Action {
    $reg = Get-ResourcePath -Name 'registry/tweaks.reg'
    if (-not (Test-Path $reg)) {
        Write-Log -Level WARN -Message "  tweaks.reg not found at $reg — skipping."
        return
    }

    $result = Import-RegFilePerValue -Path $reg -DetailLog $RegLog

    if ($result.FailCount -gt 0) {
        Write-Log -Level WARN -Message "  $($result.FailCount) of $($result.OkCount + $result.FailCount) registry values failed to import:"
        foreach ($f in $result.Failed) {
            Write-Log -Level WARN -Message ("    ! {0}\{1}  (exit {2}): {3}" -f $f.Key, $f.Value, $f.ExitCode, $f.Output)
        }
        Write-Log -Level WARN -Message "  Detailed log: $RegLog"
        if ($result.OkCount -eq 0) {
            throw "All $($result.FailCount) registry values failed to import. See $RegLog"
        }
    } else {
        Write-Log -Level DEBUG -Message "  All $($result.OkCount) values imported OK"
    }
}
