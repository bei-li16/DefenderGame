param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',
    [string]$GodotConsole = 'D:\Software\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe'
)

$ErrorActionPreference = 'Stop'

$repository = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not (Test-Path -LiteralPath $GodotConsole -PathType Leaf)) {
    throw "Godot console executable not found: $GodotConsole"
}

$worktreeChanges = & git -C $repository status --porcelain --untracked-files=normal
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to inspect Git status before building.'
}
if ($worktreeChanges) {
    throw "The worktree must be clean so the build manifest Git SHA describes all exported sources.`n$worktreeChanges"
}

& $GodotConsole --headless --path $repository --script 'res://tools/validate_content.gd'
if ($LASTEXITCODE -ne 0) {
    throw 'Content validation failed; Windows export was not attempted.'
}

foreach ($testScript in @('res://tests/run_all.gd', 'res://tests/stage_autoplay.gd')) {
    & $GodotConsole --headless --path $repository --script $testScript
    if ($LASTEXITCODE -ne 0) {
        throw "Required headless test failed: $testScript"
    }
}

& $GodotConsole --headless --path $repository --script 'res://tools/write_godot_copyright.gd'
if ($LASTEXITCODE -ne 0) {
    throw 'Godot and third-party notice generation failed; Windows export was not attempted.'
}
$noticeChanges = & git -C $repository status --porcelain -- 'release/GODOT_COPYRIGHT.txt'
if ($noticeChanges) {
    throw 'Godot notice metadata changed. Review and commit release\GODOT_COPYRIGHT.txt before exporting.'
}

$gameLicense = Join-Path $repository 'release\GAME_LICENSE.txt'
if (-not (Test-Path -LiteralPath $gameLicense -PathType Leaf)) {
    throw 'Publisher license decision is required: create release\GAME_LICENSE.txt before exporting a distributable build.'
}

& $GodotConsole --headless --path $repository --script 'res://tools/write_build_manifest.gd'
if ($LASTEXITCODE -ne 0) {
    throw 'Build manifest generation failed; Windows export was not attempted.'
}

$templateName = if ($Configuration -eq 'Debug') { 'windows_debug_x86_64.exe' } else { 'windows_release_x86_64.exe' }
$templatePath = Join-Path $env:APPDATA "Godot\export_templates\4.7.2.stable\$templateName"
if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
    throw "Matching Godot 4.7.2 export template is not installed: $templatePath"
}

$outputDirectory = if ($Configuration -eq 'Debug') { 'Builds\Windows-Dev' } else { 'Builds\Windows' }
$outputPath = Join-Path $repository "$outputDirectory\DefenderGame.exe"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputPath) | Out-Null
$exportSwitch = if ($Configuration -eq 'Debug') { '--export-debug' } else { '--export-release' }
& $GodotConsole --headless --path $repository $exportSwitch 'Windows Desktop' $outputPath
if ($LASTEXITCODE -ne 0) {
    throw "Windows $Configuration export failed with exit code $LASTEXITCODE."
}

$pckPath = [System.IO.Path]::ChangeExtension($outputPath, '.pck')
if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf) -or -not (Test-Path -LiteralPath $pckPath -PathType Leaf)) {
    throw 'Export reported success but the expected EXE/PCK pair is incomplete.'
}

if ($Configuration -eq 'Release') {
    $releaseReadme = Join-Path $repository 'release\README.txt'
    $godotCopyright = Join-Path $repository 'release\GODOT_COPYRIGHT.txt'
    $releaseDirectory = Split-Path -Parent $outputPath
    $packagedReadme = Join-Path $releaseDirectory 'README.txt'
    $packagedGameLicense = Join-Path $releaseDirectory 'GAME_LICENSE.txt'
    $packagedGodotCopyright = Join-Path $releaseDirectory 'GODOT_COPYRIGHT.txt'
    Copy-Item -LiteralPath $releaseReadme -Destination $packagedReadme -Force
    Copy-Item -LiteralPath $gameLicense -Destination $packagedGameLicense -Force
    Copy-Item -LiteralPath $godotCopyright -Destination $packagedGodotCopyright -Force
    $archivePath = Join-Path $repository 'Builds\Aegis-of-Ember-0.1.0-Windows-x64.zip'
    if (Test-Path -LiteralPath $archivePath -PathType Leaf) {
        Remove-Item -LiteralPath $archivePath -Force
    }
    Compress-Archive -LiteralPath @($outputPath, $pckPath, $packagedReadme, $packagedGameLicense, $packagedGodotCopyright) -DestinationPath $archivePath -CompressionLevel Optimal
    Write-Output "[BUILD] PASS: $outputPath and $archivePath"
} else {
    Write-Output "[BUILD] PASS: $outputPath"
}
