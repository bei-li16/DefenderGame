param(
    [Parameter(Mandatory = $true)]
    [string]$ExePath,
    [Parameter(Mandatory = $true)]
    [string]$PckPath,
    [Parameter(Mandatory = $true)]
    [string]$ExpectedGitSha,
    [string]$GodotConsole = 'D:\Software\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe'
)

$ErrorActionPreference = 'Stop'

$repository = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$resolvedExe = (Resolve-Path -LiteralPath $ExePath).Path
$resolvedPck = (Resolve-Path -LiteralPath $PckPath).Path
if (-not (Test-Path -LiteralPath $GodotConsole -PathType Leaf)) {
    throw "Godot console executable not found: $GodotConsole"
}
if ($ExpectedGitSha -notmatch '^[0-9a-f]{40}$') {
    throw 'ExpectedGitSha must be a full 40-character lowercase Git commit.'
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$isElevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isElevated) {
    throw 'Windows package acceptance must run from a non-elevated process for AT-020.'
}

$probeDirectory = Join-Path $repository "Builds\WindowsPackageProbe\$ExpectedGitSha"
New-Item -ItemType Directory -Force -Path $probeDirectory | Out-Null
$probeScript = Join-Path $repository 'tools\verify_export_pack.gd'
Push-Location $probeDirectory
try {
    & $GodotConsole --headless --main-pack $resolvedPck --script $probeScript -- "--expected-git-sha=$ExpectedGitSha"
    if ($LASTEXITCODE -ne 0) {
        throw 'The exported PCK content probe found missing, stale, or forbidden resources.'
    }
}
finally {
    Pop-Location
}

$runId = [Guid]::NewGuid().ToString('N')
$runDirectory = Join-Path $probeDirectory $runId
$gameDirectory = Join-Path $runDirectory 'game'
New-Item -ItemType Directory -Force -Path $gameDirectory | Out-Null
# Run a copy of the package: the new save contract puts savedata/ beside the
# EXE, so the probe must not touch the real distribution directory.
Copy-Item -LiteralPath $resolvedExe -Destination (Join-Path $gameDirectory 'DefenderGame.exe') -Force
Copy-Item -LiteralPath $resolvedPck -Destination (Join-Path $gameDirectory 'DefenderGame.pck') -Force
$probeExe = Join-Path $gameDirectory 'DefenderGame.exe'
$isolatedAppData = Join-Path $runDirectory 'AppData'
New-Item -ItemType Directory -Force -Path $isolatedAppData | Out-Null
$startupLog = Join-Path $runDirectory 'exported-startup.log'
$previousAppData = $env:APPDATA
try {
    $env:APPDATA = $isolatedAppData
    $quotedStartupLog = '"' + $startupLog.Replace('"', '\"') + '"'
    $arguments = @('--headless', '--quit-after', '120', '--log-file', $quotedStartupLog)
    $process = Start-Process -FilePath $probeExe -ArgumentList $arguments -WorkingDirectory $gameDirectory -WindowStyle Hidden -Wait -PassThru
}
finally {
    $env:APPDATA = $previousAppData
}
if ($process.ExitCode -ne 0) {
    throw "The exported Windows executable failed with exit code $($process.ExitCode)."
}
if (-not (Test-Path -LiteralPath $startupLog -PathType Leaf)) {
    throw 'The exported Windows executable did not create its startup log.'
}
$startupText = Get-Content -Raw -LiteralPath $startupLog
if ($startupText -match '(?im)^\s*(SCRIPT ERROR|ERROR:)') {
    throw "The exported Windows executable reported an engine or script error.`n$startupText"
}

# Portable saves: first launch must materialize the active slot file and the
# settings file inside savedata/ next to the EXE (AT-020 non-elevated write).
foreach ($requiredSave in @('slot_1.json', 'settings.json')) {
    $savePath = Join-Path (Join-Path $gameDirectory 'savedata') $requiredSave
    if (-not (Test-Path -LiteralPath $savePath -PathType Leaf)) {
        throw "The exported game did not create $requiredSave in the portable savedata directory beside the EXE."
    }
}

Write-Output "[WINDOWS EXPORT] PASS: non_elevated=$(-not $isElevated) commit=$ExpectedGitSha exe=$resolvedExe pck=$resolvedPck"
