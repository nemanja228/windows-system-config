function Get-StepSummary {
<#
.SYNOPSIS
    Return the per-step summary collected by Invoke-Step during this session.

.OUTPUTS
    [System.Collections.Generic.List[object]] — the live list. Each item has
    Name, Success, Skipped, Filtered, DurationSec, Error, Tags.

.NOTES
    Bootstrap uses this for the final pass/fail exit code; the inner list is
    populated by Invoke-Step calls and reset by Initialize-Logging.
#>
    [CmdletBinding()]
    param()
    return $script:Summary
}
