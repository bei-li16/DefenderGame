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

foreach ($testScript in @('res://tests/run_all.gd', 'res://tests/endless_stages_acceptance.gd', 'res://tests/endless_research_acceptance.gd', 'res://tests/stage_autoplay.gd', 'res://tests/save_slot_acceptance.gd')) {
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

& (Join-Path $PSScriptRoot 'run_pack_preflight.ps1') -GodotConsole $GodotConsole
if ($LASTEXITCODE -ne 0) {
    throw 'Template-free PCK preflight failed; Windows export was not attempted.'
}

$gameLicense = Join-Path $repository 'release\GAME_LICENSE.txt'
if (-not (Test-Path -LiteralPath $gameLicense -PathType Leaf)) {
    throw 'Publisher license decision is required: create release\GAME_LICENSE.txt before exporting a distributable build.'
}
$gameLicenseText = Get-Content -Raw -LiteralPath $gameLicense
if ($gameLicenseText.Length -lt 100 -or $gameLicenseText -match '\{\{[^}]+\}\}|<YEAR>|<COPYRIGHT HOLDER>|(?i)\bTODO\b') {
    throw 'release\GAME_LICENSE.txt is empty, incomplete, or still contains placeholders.'
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

$gitSha = (& git -C $repository rev-parse HEAD).Trim()
& (Join-Path $PSScriptRoot 'verify_windows_export.ps1') -ExePath $outputPath -PckPath $pckPath -ExpectedGitSha $gitSha -GodotConsole $GodotConsole
if ($LASTEXITCODE -ne 0) {
    throw 'Exported Windows package acceptance failed.'
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
    $archivePath = Join-Path $repository 'Builds\Aegis-of-Ember-1.4.0-Windows-x64.zip'
    if (Test-Path -LiteralPath $archivePath -PathType Leaf) {
        Remove-Item -LiteralPath $archivePath -Force
    }
    # Antivirus scanners transiently lock the freshly exported EXE and fail the
    # first Compress-Archive with UnauthorizedAccess.  Wait and retry once.
    $archiveInputs = @($outputPath, $pckPath, $packagedReadme, $packagedGameLicense, $packagedGodotCopyright)
    try {
        Compress-Archive -LiteralPath $archiveInputs -DestinationPath $archivePath -CompressionLevel Optimal
    } catch [System.IO.IOException] {
        Write-Output "[BUILD] ZIP packaging hit an IO lock, retrying once after 8s"
        Start-Sleep -Seconds 8
        Compress-Archive -LiteralPath $archiveInputs -DestinationPath $archivePath -CompressionLevel Optimal
    }
    Write-Output "[BUILD] PASS: $outputPath and $archivePath"
} else {
    Write-Output "[BUILD] PASS: $outputPath"
}
