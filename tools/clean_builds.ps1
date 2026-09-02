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
foreach ($file in $tempFiles) {
    Remove-Item -LiteralPath $file.FullName -Force
    Write-Host "Removed $($file.FullName.Substring($builds.Length + 1))"
}

Write-Host "Probe residue cleaned; release artifacts in Builds/Windows and the portable ZIP were kept."
