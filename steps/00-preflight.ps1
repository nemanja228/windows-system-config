# =============================================================================
# 00 — Pre-flight gates (no tags — always run)
#
# Run standalone with:
#   Import-Module .\lib\WinSetup; Initialize-Logging; . .\steps\00-preflight.ps1
# =============================================================================

Invoke-Step -Name "Pre-flight: admin check" -Action {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Not running as Administrator."
    }
    Write-Log -Level DEBUG -Message "  Running as Administrator: OK"
}

Invoke-Step -Name "Pre-flight: Windows build" -ContinueOnError -Action {
    $build   = [System.Environment]::OSVersion.Version.Build
    $caption = (Get-CimInstance Win32_OperatingSystem).Caption
    Write-Log -Level DEBUG -Message "  $caption (build $build)"
    if ($build -lt 26100) {
        Write-Log -Level WARN -Message "  Build older than 24H2 (26100). Some features won't apply."
    }
}

Invoke-Step -Name "Pre-flight: network connectivity" -ContinueOnError -Action {
    $reachable = Test-Connection -ComputerName 'github.com' -Count 1 -Quiet -ErrorAction SilentlyContinue
    if (-not $reachable) {
        $reachable = Test-Connection -ComputerName '1.1.1.1' -Count 1 -Quiet -ErrorAction SilentlyContinue
    }
    if (-not $reachable) {
        throw "No network connectivity to github.com or 1.1.1.1"
    }
    Write-Log -Level DEBUG -Message "  Network OK"
}

Invoke-Step -Name "Pre-flight: set execution policy (process scope)" -Action {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
    Write-Log -Level DEBUG -Message "  Policy: Bypass (process)"
}
