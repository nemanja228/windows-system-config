<#
.SYNOPSIS
    Restore a MyASUS snapshot produced by Export-MyASUSConfig.ps1.

.DESCRIPTION
    Imports every `*.reg` file in -InputDir under
    `HKLM\SOFTWARE\ASUS\ASUS System Control Interface\AsusOptimization\`,
    then restarts the relevant ASUS services (ASUSOptimization,
    AsusAppService, AsusPTPService) so they re-read the registry and
    push values to firmware via their ACPI / EC plumbing.

    Requires elevation (HKLM write).

    Bits that won't take effect immediately:
      - Battery-charge threshold (firmware-stored; ASUSOptimization service
        on next start writes to EC).
      - Fan-profile defaults pre-baked into the EC.

    A reboot after import gives the cleanest result. The script doesn't
    reboot for you.

.PARAMETER InputDir
    Snapshot directory produced by Export-MyASUSConfig.ps1. Must contain
    at least one HKLM-ASUS-*.reg file.

.PARAMETER NoRestart
    Skip the service restart step. Useful when running Import as part of
    a larger bootstrap that will reboot anyway.

.EXAMPLE
    .\Import-MyASUSConfig.ps1 -InputDir 'D:\data\3_library\machine-snapshots\zenbook-myasus'
    # Restore from a curated snapshot directory.

.EXAMPLE
    .\Import-MyASUSConfig.ps1 -InputDir "$env:TEMP\myasus-test" -WhatIf
    # Preview the imports and service restarts without changing anything.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$InputDir,

    [switch]$NoRestart
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $InputDir)) {
    Write-Error "Snapshot directory not found: $InputDir"
    exit 1
}

# Require admin for actual writes (HKLM\... + service restart). Skip the
# check under -WhatIf so dry-runs work without elevation.
if (-not $WhatIfPreference) {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Error "Importing HKLM\SOFTWARE\ASUS requires elevation. Re-run from elevated PowerShell."
        exit 1
    }
}

# Sanity-check: this machine actually has the SCI tree, so the import won't
# orphan keys.
$RootKey = 'HKLM:\SOFTWARE\ASUS\ASUS System Control Interface\AsusOptimization'
if (-not (Test-Path $RootKey)) {
    Write-Warning "Target machine has no $RootKey -- importing anyway, but ASUS service may not be installed yet."
}

$regFiles = @(Get-ChildItem -Path $InputDir -Filter 'HKLM-ASUS-*.reg' -File -ErrorAction SilentlyContinue)
if ($regFiles.Count -eq 0) {
    Write-Error "No HKLM-ASUS-*.reg files in $InputDir"
    exit 1
}

Write-Host "Importing from: $InputDir" -ForegroundColor Cyan
Write-Host "  $($regFiles.Count) .reg file(s) found." -ForegroundColor DarkGray

foreach ($reg in $regFiles) {
    if ($PSCmdlet.ShouldProcess($reg.FullName, "reg import")) {
        & reg.exe import $reg.FullName *>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "reg import of '$($reg.Name)' returned exit $LASTEXITCODE"
        } else {
            Write-Host "  imported: $($reg.Name)" -ForegroundColor DarkGray
        }
    }
}

if ($NoRestart) {
    Write-Host ""
    Write-Host "Skipped service restart (-NoRestart). Reboot to apply firmware-side bits." -ForegroundColor Yellow
    return
}

# Bounce ASUS services so they re-read the registry. Order doesn't matter
# much; ASUSOptimization is the one most likely to sync EC firmware bits.
$services = @('ASUSOptimization', 'AsusAppService', 'AsusPTPService')

Write-Host ""
foreach ($svc in $services) {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if (-not $s) {
        Write-Host "  skip: $svc (not installed)" -ForegroundColor DarkGray
        continue
    }
    if ($PSCmdlet.ShouldProcess($svc, "Restart-Service")) {
        try {
            Restart-Service -Name $svc -Force -ErrorAction Stop
            Write-Host "  restarted: $svc" -ForegroundColor Green
        } catch {
            Write-Warning "Failed to restart ${svc}: $($_.Exception.Message)"
        }
    }
}

Write-Host ""
Write-Host "Import complete. Verify in MyASUS UI." -ForegroundColor Green
Write-Host "A reboot is recommended for firmware-side bits (battery threshold, EC fan profile)." -ForegroundColor Yellow
