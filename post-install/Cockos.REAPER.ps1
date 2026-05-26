# Post-install hook for Cockos.REAPER — runs after winget installs REAPER.
# Adds REAPER's media-project directory to Defender exclusions so real-time
# scans don't introduce DPC spikes during recording/playback (ASIO buffer
# underruns surface immediately if Defender scans a project file mid-take).
#
# Both casings are added because REAPER's auto-created project dir name
# varies by version + Windows locale (some installs land 'Reaper Media',
# others 'REAPER Media'). Add-MpPreference is idempotent — listing a path
# that doesn't exist yet is fine; the exclusion takes effect when the
# directory appears.

Add-DefenderExclusion -Path @(
    "$env:USERPROFILE\Documents\Reaper Media",
    "$env:USERPROFILE\Documents\REAPER Media"
) -Source 'reaper'
