param(
    [string]$GodotConsole = 'D:\Software\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe',
    [switch]$SkipPackPreflight
)

$ErrorActionPreference = 'Stop'

$repository = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$checks = [Collections.Generic.List[object]]::new()

function Add-ReadinessCheck {
    param(
        [string]$Name,
        [bool]$Ready,
        [string]$Detail
    )
    $checks.Add([ordered]@{
        name = $Name
        ready = $Ready
        detail = $Detail
    })
}

$branch = (& git -C $repository branch --show-current).Trim()
$gitSha = (& git -C $repository rev-parse HEAD).Trim()
$gitAvailable = $LASTEXITCODE -eq 0 -and $gitSha -match '^[0-9a-f]{40}$'
Add-ReadinessCheck 'branch' ($branch -eq 'windows-godot') "current=$branch"
Add-ReadinessCheck 'git_commit' $gitAvailable "commit=$gitSha"

$worktreeChanges = @(& git -C $repository status --porcelain --untracked-files=normal)
$worktreeClean = $LASTEXITCODE -eq 0 -and $worktreeChanges.Count -eq 0
Add-ReadinessCheck 'clean_worktree' $worktreeClean ($(if ($worktreeClean) { 'clean' } else { ($worktreeChanges -join '; ') }))

$godotExists = Test-Path -LiteralPath $GodotConsole -PathType Leaf
$godotVersion = ''
if ($godotExists) {
    $godotVersion = (& $GodotConsole --version | Select-Object -First 1).Trim()
}
$godotMatches = $godotExists -and $godotVersion.StartsWith('4.7.2.stable')
Add-ReadinessCheck 'godot_4_7_2' $godotMatches ($(if ($godotExists) { "version=$godotVersion" } else { "missing=$GodotConsole" }))

$presetPath = Join-Path $repository 'export_presets.cfg'
$presetReady = Test-Path -LiteralPath $presetPath -PathType Leaf
if ($presetReady) {
    $presetText = Get-Content -Raw -LiteralPath $presetPath
    $presetReady = $presetText -match '(?m)^name="Windows Desktop"$' -and $presetText -match '(?m)^binary_format/embed_pck=false$'
}
Add-ReadinessCheck 'windows_export_preset' $presetReady 'preset=Windows Desktop; separate EXE/PCK required'

$releaseReadme = Join-Path $repository 'release\README.txt'
$godotNotice = Join-Path $repository 'release\GODOT_COPYRIGHT.txt'
Add-ReadinessCheck 'release_readme' (Test-Path -LiteralPath $releaseReadme -PathType Leaf) 'release/README.txt'
Add-ReadinessCheck 'godot_notices' (Test-Path -LiteralPath $godotNotice -PathType Leaf) 'release/GODOT_COPYRIGHT.txt'

$gameLicense = Join-Path $repository 'release\GAME_LICENSE.txt'
$gameLicenseReady = Test-Path -LiteralPath $gameLicense -PathType Leaf
$gameLicenseDetail = 'missing; choose license type and copyright holder'
if ($gameLicenseReady) {
    $licenseText = Get-Content -Raw -LiteralPath $gameLicense
    $gameLicenseReady = $licenseText.Length -ge 100 -and $licenseText -notmatch '\{\{[^}]+\}\}|<YEAR>|<COPYRIGHT HOLDER>|(?i:\bTODO\b)'
    $gameLicenseDetail = if ($gameLicenseReady) { 'release/GAME_LICENSE.txt validated' } else { 'file exists but is incomplete or contains placeholders' }
}
Add-ReadinessCheck 'game_license' $gameLicenseReady $gameLicenseDetail

$debugTemplateRelative = 'Godot\export_templates\4.7.2.stable\windows_debug_x86_64.exe'
$releaseTemplateRelative = 'Godot\export_templates\4.7.2.stable\windows_release_x86_64.exe'
$debugTemplate = Join-Path $env:APPDATA $debugTemplateRelative
$releaseTemplate = Join-Path $env:APPDATA $releaseTemplateRelative
Add-ReadinessCheck 'debug_export_template' (Test-Path -LiteralPath $debugTemplate -PathType Leaf) "%APPDATA%\$debugTemplateRelative"
Add-ReadinessCheck 'release_export_template' (Test-Path -LiteralPath $releaseTemplate -PathType Leaf) "%APPDATA%\$releaseTemplateRelative"

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$isElevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Add-ReadinessCheck 'non_elevated_acceptance_host' (-not $isElevated) "elevated=$isElevated"

$packPreflightReady = $false
$packPreflightDetail = 'skipped by request'
if (-not $SkipPackPreflight) {
    if ($worktreeClean -and $godotMatches) {
        & (Join-Path $PSScriptRoot 'run_pack_preflight.ps1') -GodotConsole $GodotConsole
        $packPreflightReady = $LASTEXITCODE -eq 0
        $packPreflightDetail = if ($packPreflightReady) { "commit=$gitSha" } else { "failed with exit code $LASTEXITCODE" }
    }
    else {
        $packPreflightDetail = 'requires a clean worktree and Godot 4.7.2'
    }
}
else {
    $packPreflightReady = $false
    $packPreflightDetail = 'skipped; run without -SkipPackPreflight for a release-ready result'
}
Add-ReadinessCheck 'template_free_pck_preflight' $packPreflightReady $packPreflightDetail

$readyCount = @($checks | Where-Object { $_.ready }).Count
$blockers = @($checks | Where-Object { -not $_.ready })
foreach ($check in $checks) {
    $label = if ($check.ready) { 'READY' } else { 'BLOCKED' }
    Write-Output "[$label] $($check.name): $($check.detail)"
}

$report = [ordered]@{
    generated_utc = [DateTime]::UtcNow.ToString('o')
    branch = $branch
    git_commit = $gitSha
    ready = $blockers.Count -eq 0
    ready_count = $readyCount
    total_count = $checks.Count
    blockers = @($blockers | ForEach-Object { $_.name })
    checks = $checks
}
$reportDirectory = Join-Path $repository 'Builds\ReleaseReadiness'
New-Item -ItemType Directory -Force -Path $reportDirectory | Out-Null
$reportPath = Join-Path $reportDirectory 'release-readiness.json'
$utf8WithoutBom = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 6) + [Environment]::NewLine, $utf8WithoutBom)
Write-Output "[READINESS] $readyCount/$($checks.Count) ready; blockers=$($blockers.Count); report=$reportPath"
exit $(if ($blockers.Count -eq 0) { 0 } else { 2 })
