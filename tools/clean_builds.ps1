# Removes local build-probe residue from Builds/ while keeping release artifacts.
# Usage:
#   .\tools\clean_builds.ps1           # remove probe/test residue, keep Windows/, ZIP and manifest
#   .\tools\clean_builds.ps1 -All      # remove the entire Builds/ content except .gdignore
param(
    [switch]$All
)

$ErrorActionPreference = "Stop"
$builds = Join-Path $PSScriptRoot "..\Builds"
if (-not (Test-Path $builds)) {
    Write-Host "Builds/ does not exist; nothing to clean."
    exit 0
}

$probeDirectories = @(
    "PackPreflight",
    "WindowsPackageProbe",
    "SaveCrashTest",
    "RuntimeProbe",
    "ReleaseReadiness",
    "LicensePreflight"
)

if ($All) {
    Get-ChildItem -LiteralPath $builds -Force | Where-Object { $_.Name -ne ".gdignore" } | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Recurse -Force
        Write-Host "Removed $($_.Name)"
    }
    Write-Host "Builds/ cleaned."
    exit 0
}

foreach ($name in $probeDirectories) {
    $path = Join-Path $builds $name
    if (Test-Path $path) {
        Remove-Item -LiteralPath $path -Recurse -Force
        Write-Host "Removed Builds/$name"
    }
}

$tempFiles = Get-ChildItem -LiteralPath $builds -Recurse -Force -File |
    Where-Object { $_.Extension -eq ".tmp" -or $_.Extension -eq ".log" }
$locked = 0
foreach ($file in $tempFiles) {
    try {
        Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
        Write-Host "Removed $($file.FullName.Substring($builds.Length + 1))"
    }
    catch {
        # Files locked by a running process (for example a game instance still
        # holding the previous build) are reported and left in place.
        $locked += 1
        Write-Warning "Locked, left in place: $($file.FullName.Substring($builds.Length + 1))"
    }
}

Write-Host "Probe residue cleaned; release artifacts in Builds/Windows and the portable ZIP were kept."
if ($locked -gt 0) {
    Write-Host "$locked locked file(s) were skipped; close the owning process and re-run if needed."
}
exit 0
