# Post-install hook for Microsoft.DotNet.SDK.10 — runs after winget installs
# the .NET 10 SDK. Adds the user nuget cache to Defender exclusions so
# restore-heavy operations (nuget restore, dotnet build, dotnet tool install)
# don't get scanned per-file.
#
# Idempotent: Add-MpPreference -ExclusionPath no-ops on an already-excluded path.

Add-DefenderExclusion -Path "$env:USERPROFILE\.nuget" -Source 'dotnet'
