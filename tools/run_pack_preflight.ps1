param(
    [string]$GodotConsole = 'D:\Software\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe'
)

$ErrorActionPreference = 'Stop'

$repository = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not (Test-Path -LiteralPath $GodotConsole -PathType Leaf)) {
    throw "Godot console executable not found: $GodotConsole"
}

$worktreeChanges = & git -C $repository status --porcelain --untracked-files=normal
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to inspect Git status before PCK preflight.'
}
if ($worktreeChanges) {
    throw "The worktree must be clean so the PCK manifest describes all packed sources.`n$worktreeChanges"
}

$gitSha = (& git -C $repository rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $gitSha.Length -ne 40) {
    throw 'Unable to resolve the Git commit for PCK verification.'
}

& $GodotConsole --headless --path $repository --script 'res://tools/write_build_manifest.gd'
if ($LASTEXITCODE -ne 0) {
    throw 'Build manifest generation failed; PCK preflight was not attempted.'
}

$preflightDirectory = Join-Path $repository 'Builds\PackPreflight'
New-Item -ItemType Directory -Force -Path $preflightDirectory | Out-Null
$packPath = Join-Path $preflightDirectory 'DefenderGame-preflight.pck'
& $GodotConsole --headless --path $repository --export-pack 'Windows Desktop' $packPath
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $packPath -PathType Leaf)) {
    throw 'Godot could not create the template-free PCK preflight artifact.'
}

$probeScript = Join-Path $repository 'tools\verify_export_pack.gd'
$isolatedAppData = Join-Path $preflightDirectory 'IsolatedAppData'
New-Item -ItemType Directory -Force -Path $isolatedAppData | Out-Null
$startupLog = Join-Path $preflightDirectory 'pack-startup.log'
$previousAppData = $env:APPDATA
$startupExit = 1
Push-Location $preflightDirectory
try {
    & $GodotConsole --headless --main-pack $packPath --script $probeScript -- "--expected-git-sha=$gitSha"
    if ($LASTEXITCODE -ne 0) {
        throw 'The PCK content probe found missing, stale, or forbidden resources.'
    }
    $env:APPDATA = $isolatedAppData
    & $GodotConsole --headless --main-pack $packPath --quit-after 60 --log-file $startupLog
    $startupExit = $LASTEXITCODE
}
finally {
    $env:APPDATA = $previousAppData
    Pop-Location
}
if ($startupExit -ne 0) {
    throw "The standalone PCK startup probe failed with exit code $startupExit."
}
$startupText = Get-Content -Raw -LiteralPath $startupLog
if ($startupText -match '(?im)^\s*(SCRIPT ERROR|ERROR:)') {
    throw "The standalone PCK started but reported an engine or script error.`n$startupText"
}

$pack = Get-Item -LiteralPath $packPath
Write-Output "[PACK PREFLIGHT] PASS: commit=$gitSha bytes=$($pack.Length) path=$packPath"
