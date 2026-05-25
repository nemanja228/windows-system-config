#Requires -Version 5.1
<#
.SYNOPSIS
    Render autounattend.template.xml -> autounattend.xml.
.EXAMPLE
    .\render-autounattend.ps1
.EXAMPLE
    .\render-autounattend.ps1 -ComputerName ZENBOOK -Username nemanja -CSizeGB 400
#>

[CmdletBinding()]
param(
    [string]$TemplatePath = (Join-Path $PSScriptRoot 'autounattend.template.xml'),
    [string]$OutputPath   = (Join-Path $PSScriptRoot 'autounattend.xml'),
    [string]$ComputerName,
    [string]$Username,
    [securestring]$Password,
    [string]$Ssid,
    [securestring]$WifiPassword,
    [int]$CSizeGB = 350
)

if (-not (Test-Path $TemplatePath)) {
    Write-Error "Template not found: $TemplatePath"
    exit 1
}

if (-not $ComputerName) { $ComputerName = Read-Host "Computer name" }
if (-not $Username)     { $Username     = Read-Host "Local username" }
if (-not $Password)     { $Password     = Read-Host "Password for $Username" -AsSecureString }
if (-not $Ssid)         { $Ssid         = Read-Host "Wi-Fi SSID" }
if (-not $WifiPassword) { $WifiPassword = Read-Host "Wi-Fi password" -AsSecureString }

# SecureString -> plain (autounattend can't take SecureString)
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
try   { $plainPw = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }

$bstr2 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($WifiPassword)
try   { $plainWifiPw = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr2) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr2) }

# WLAN profiles need the SSID in both <name> (text) and <hex> (UTF-8 bytes, uppercase) for hidden networks.
$ssidHex = -join ([System.Text.Encoding]::UTF8.GetBytes($Ssid) | ForEach-Object { '{0:X2}' -f $_ })

$subs = @{
    '_COMPUTERNAME_' = $ComputerName
    '_ACCOUNTNAME_'  = $Username
    '_PASSWORD_'     = $plainPw
    '_CSizeMB_'      = ($CSizeGB * 1024).ToString()
    '_SSID_'         = $Ssid
    '_WPA2PASSWORD_' = $plainWifiPw
    '5F535349445F'   = $ssidHex
}

$content = Get-Content $TemplatePath -Raw
foreach ($k in $subs.Keys) {
    $escaped = [System.Security.SecurityElement]::Escape($subs[$k])
    $content = $content.Replace($k, $escaped)
}

$remaining = [regex]::Matches($content, '\{\{[A-Za-z_]+\}\}') |
             ForEach-Object { $_.Value } | Sort-Object -Unique
if ($remaining) {
    Write-Warning "Unfilled placeholders: $($remaining -join ', ')"
}

Set-Content -Path $OutputPath -Value $content -Encoding UTF8 -Force

$plainPw     = $null
$plainWifiPw = $null
[GC]::Collect()

Write-Host ""
Write-Host "Rendered: $OutputPath" -ForegroundColor Green
Write-Host "C: size:  $CSizeGB GB ($($CSizeGB * 1024) MB)" -ForegroundColor Gray
Write-Host "Copy to USB root, install, then delete this file." -ForegroundColor Yellow