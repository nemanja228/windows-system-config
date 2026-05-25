#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Diagnoses partial-write failures in a .reg file by importing each value individually.

.DESCRIPTION
    `reg import` continues past errors and only prints a generic "Not all data was successfully
    written" summary, so it's painful to know which specific entry caused the warning.

    This script splits the .reg file into one-value temp files, imports each, and reports the
    offenders with key path + value name + the actual reg.exe output. Multi-line binary values
    (rare in our tweaks.reg) are detected and imported as a single unit per value.

.PARAMETER Path
    Path to the .reg file. Defaults to ..\tweaks.reg relative to this script.

.EXAMPLE
    .\additions\Test-RegImport.ps1
    .\additions\Test-RegImport.ps1 -Path .\tweaks.reg
#>

[CmdletBinding()]
param(
    [string]$Path = (Join-Path $PSScriptRoot '..\tweaks.reg')
)

if (-not (Test-Path $Path)) {
    Write-Error "File not found: $Path"
    exit 1
}

$content  = Get-Content -Path $Path -Raw
$splitIdx = $content.IndexOf("`n[")
if ($splitIdx -lt 0) {
    Write-Error "No [HKEY_*] sections found in $Path"
    exit 1
}

# Header = file header (version line + comments) up to the first [KEY] block
$header = $content.Substring(0, $splitIdx + 1).TrimEnd()
$rest   = $content.Substring($splitIdx + 1)

# Split blocks at each line that starts with '['
$blocks = $rest -split '(?m)(?=^\[)'

$failed  = New-Object System.Collections.Generic.List[pscustomobject]
$okCount = 0

foreach ($block in $blocks) {
    if ([string]::IsNullOrWhiteSpace($block)) { continue }

    # Re-join continuation lines (lines ending with backslash) so multi-line binary values stay intact
    $joined = $block -replace '\\\s*\r?\n\s*', ''
    $lines  = $joined -split "`r?`n"

    $keyHeader = $lines[0].Trim()
    if (-not $keyHeader.StartsWith('[')) { continue }

    foreach ($line in $lines[1..($lines.Length - 1)]) {
        $t = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($t)) { continue }
        if ($t.StartsWith(';'))                { continue }   # comment
        # Match real value lines:   "Name"=...   or   @=...
        if ($t -notmatch '^("[^"]*"|@)\s*=') { continue }

        # Build a single-value .reg file
        $regBody = "$header`r`n`r`n$keyHeader`r`n$t`r`n"
        $tmp     = Join-Path $env:TEMP ("regprobe-{0}.reg" -f [guid]::NewGuid())
        Set-Content -LiteralPath $tmp -Value $regBody -Encoding ASCII

        $out  = & reg.exe import $tmp 2>&1
        $code = $LASTEXITCODE
        Remove-Item -LiteralPath $tmp -Force

        $valueName = if ($t.StartsWith('@')) { '(Default)' } else { ($t -split '=', 2)[0].Trim('"') }

        if ($code -ne 0) {
            $failed.Add([pscustomobject]@{
                Key      = $keyHeader
                Value    = $valueName
                Line     = $t
                ExitCode = $code
                Output   = ($out -join ' | ')
            })
            Write-Host ("FAIL  {0,-3}  {1}\{2}" -f $code, $keyHeader.Trim('[',']'), $valueName) -ForegroundColor Red
        } else {
            $okCount++
            Write-Host ("OK    {0,-3}  {1}\{2}" -f $code, $keyHeader.Trim('[',']'), $valueName) -ForegroundColor DarkGreen
        }
    }
}

Write-Host ""
Write-Host ("Summary: {0} OK, {1} FAILED" -f $okCount, $failed.Count) -ForegroundColor Cyan

if ($failed.Count -gt 0) {
    Write-Host ""
    Write-Host "FAILED ENTRIES:" -ForegroundColor Red
    $failed | Format-List Key, Value, Line, ExitCode, Output
}

exit $failed.Count
