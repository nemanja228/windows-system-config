<#
.SYNOPSIS
    Reusable logging helpers for win-setup-style automation scripts.

.DESCRIPTION
    Dot-source from a script:

        . "$PSScriptRoot\lib\Logging.ps1"
        Initialize-Logging                  # set up log file + state
        # (optional) restrict which steps run by tag:
        Set-LoggingFilter -Steps debloat,privacy -DryRun:$false

        Invoke-Step -Name "Do thing" -Tags @('core','example') -Action { ... }
        Show-Summary

    Provides:
      Initialize-Logging      — set up timestamped log file, init state
      Set-LoggingFilter       — restrict which Invoke-Step calls execute
      Write-Log               — colour-coded console + file logger
      Invoke-Step             — wraps a scriptblock with start/end logging,
                                timing, exception capture, dry-run skip,
                                and tag-based filtering
      Show-Summary            — final pass/fail/skipped table

    Script-scoped state (set by Initialize-Logging in the *consuming* script):
      $script:LogFile         — path to the active log file
      $script:LogDir          — directory containing logs
      $script:LogStamp        — yyyyMMdd-HHmmss used in filenames
      $script:Summary         — list of per-step result objects
      $script:ActiveSteps     — tag filter (null/empty = run all)
      $script:LogDryRun       — whether to skip destructive actions

    The $script: scope refers to the SOURCING script when dot-sourced, so each
    script gets its own log file and summary without collision.

.NOTES
    Tested on PowerShell 5.1 and PowerShell 7+.
    No external dependencies.
#>

# =============================================================================
# Initialize-Logging
# =============================================================================

function Initialize-Logging {
    [CmdletBinding()]
    param(
        [string]$LogDir = (Join-Path $env:USERPROFILE 'win-setup-logs'),
        [string]$LogPrefix = 'bootstrap'
    )

    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

    $script:LogFile     = Join-Path $LogDir "$LogPrefix-$stamp.log"
    $script:LogDir      = $LogDir
    $script:LogStamp    = $stamp
    $script:Summary     = New-Object System.Collections.Generic.List[object]
    $script:ActiveSteps = $null
    $script:LogDryRun   = $false

    return [PSCustomObject]@{
        LogFile = $script:LogFile
        LogDir  = $script:LogDir
        Stamp   = $stamp
    }
}

# =============================================================================
# Set-LoggingFilter — call after Initialize-Logging to restrict scope
# =============================================================================

function Set-LoggingFilter {
    [CmdletBinding()]
    param(
        [string[]]$Steps,
        [bool]$DryRun = $false
    )

    if ($Steps -and $Steps.Count -gt 0) {
        $script:ActiveSteps = $Steps | ForEach-Object { $_.ToLowerInvariant() }
    } else {
        $script:ActiveSteps = $null
    }
    $script:LogDryRun = $DryRun
}

# =============================================================================
# Write-Log
# =============================================================================

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)][AllowEmptyString()][string]$Message,
        [ValidateSet('INFO','WARN','ERROR','SUCCESS','STEP','DEBUG','TRACE')]
        [string]$Level = 'INFO'
    )
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [$($Level.PadRight(7))] $Message"
    $color = switch ($Level) {
        'INFO'    { 'Gray' }
        'WARN'    { 'Yellow' }
        'ERROR'   { 'Red' }
        'SUCCESS' { 'Green' }
        'STEP'    { 'Cyan' }
        'DEBUG'   { 'DarkGray' }
        'TRACE'   { 'DarkGray' }
        default   { 'White' }
    }
    Write-Host $line -ForegroundColor $color
    if ($script:LogFile) {
        try {
            Add-Content -Path $script:LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
        } catch {
            Write-Host "  [log write failed: $($_.Exception.Message)]" -ForegroundColor Red
        }
    }
}

# =============================================================================
# Invoke-Step
# =============================================================================

function Invoke-Step {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][scriptblock]$Action,
        [string[]]$Tags = @(),
        [switch]$ContinueOnError,
        [switch]$SkipOnDryRun
    )

    # ---- Tag-based filtering ----
    # No tags on the step => always runs (good for pre-flight gates).
    # Tags present + filter active => run only if at least one tag matches.
    if ($Tags.Count -gt 0 -and $script:ActiveSteps -and $script:ActiveSteps.Count -gt 0) {
        $lowerTags = $Tags | ForEach-Object { $_.ToLowerInvariant() }
        $match = $lowerTags | Where-Object { $script:ActiveSteps -contains $_ }
        if (-not $match) {
            $result = [PSCustomObject]@{
                Name        = $Name
                Success     = $true
                Skipped     = $true
                Filtered    = $true
                DurationSec = 0.0
                Error       = $null
                Tags        = ($Tags -join ',')
            }
            $script:Summary.Add($result)
            return
        }
    }

    Write-Log -Level STEP -Message ""
    Write-Log -Level STEP -Message "==> $Name"
    if ($Tags.Count -gt 0) {
        Write-Log -Level DEBUG -Message "    tags: $($Tags -join ',')"
    }

    $start = Get-Date
    $result = [PSCustomObject]@{
        Name        = $Name
        Success     = $false
        Skipped     = $false
        Filtered    = $false
        DurationSec = 0.0
        Error       = $null
        Tags        = ($Tags -join ',')
    }

    try {
        if ($script:LogDryRun -and $SkipOnDryRun) {
            Write-Log -Level WARN -Message "  [DRY-RUN] skipping execution"
            $result.Skipped = $true
            $result.Success = $true
        } else {
            & $Action 2>&1 | ForEach-Object {
                if ($null -eq $_) { return }
                $text = $_.ToString().TrimEnd()
                if ([string]::IsNullOrWhiteSpace($text)) { return }
                if ($_ -is [System.Management.Automation.ErrorRecord]) {
                    Write-Log -Level WARN -Message "  ! $text"
                }
                elseif ($_ -is [System.Management.Automation.WarningRecord]) {
                    Write-Log -Level WARN -Message "  ? $text"
                }
                else {
                    Write-Log -Level TRACE -Message "    $text"
                }
            }
            $result.Success = $true
        }
    } catch {
        $result.Error = $_.Exception.Message
        Write-Log -Level ERROR -Message "  Exception: $($_.Exception.Message)"
        if ($_.ScriptStackTrace) {
            foreach ($l in ($_.ScriptStackTrace -split "`n")) {
                Write-Log -Level ERROR -Message "    $l"
            }
        }
        if (-not $ContinueOnError) {
            $result.DurationSec = [math]::Round(((Get-Date) - $start).TotalSeconds, 1)
            $script:Summary.Add($result)
            Show-Summary
            throw
        }
    }

    $result.DurationSec = [math]::Round(((Get-Date) - $start).TotalSeconds, 1)
    if ($result.Skipped) {
        Write-Log -Level WARN -Message "  SKIPPED ($($result.DurationSec)s)"
    } elseif ($result.Success) {
        Write-Log -Level SUCCESS -Message "  OK ($($result.DurationSec)s)"
    } else {
        Write-Log -Level ERROR -Message "  FAILED ($($result.DurationSec)s)"
    }
    $script:Summary.Add($result)
}

# =============================================================================
# Show-Summary
# =============================================================================

function Show-Summary {
    [CmdletBinding()]
    param()

    Write-Log -Level STEP -Message ""
    Write-Log -Level STEP -Message "=================== SUMMARY ==================="

    $ok       = ($script:Summary | Where-Object { $_.Success -and -not $_.Skipped }).Count
    $skipped  = ($script:Summary | Where-Object { $_.Skipped -and -not $_.Filtered }).Count
    $filtered = ($script:Summary | Where-Object { $_.Filtered }).Count
    $fail     = ($script:Summary | Where-Object { -not $_.Success }).Count

    Write-Log -Level SUCCESS -Message "Succeeded:    $ok"
    Write-Log -Level WARN    -Message "Skipped (dry):$skipped"
    Write-Log -Level INFO    -Message "Filtered out: $filtered"
    Write-Log -Level $(if ($fail) { 'ERROR' } else { 'INFO' }) -Message "Failed:       $fail"
    Write-Log -Level INFO    -Message ""

    foreach ($s in $script:Summary) {
        $marker =
            if ($s.Filtered)       { '--' }
            elseif ($s.Skipped)    { '~ ' }
            elseif ($s.Success)    { 'OK' }
            else                   { 'X ' }

        $lvl =
            if ($s.Filtered)       { 'DEBUG' }
            elseif ($s.Skipped)    { 'WARN' }
            elseif ($s.Success)    { 'INFO' }
            else                   { 'ERROR' }

        $extra = if ($s.Error) { "  -- $($s.Error)" } else { '' }
        $line  = ("  [{0}] {1}  ({2}s){3}" -f $marker, $s.Name, $s.DurationSec, $extra)
        Write-Log -Level $lvl -Message $line
    }

    Write-Log -Level STEP -Message "==============================================="
    Write-Log -Level INFO -Message ""
    if ($script:LogFile) {
        Write-Log -Level INFO -Message "Full log: $script:LogFile"
    }
}
