param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('MIT', 'Proprietary')]
    [string]$License,
    [Parameter(Mandatory = $true)]
    [string]$CopyrightHolder,
    [ValidateRange(1970, 2100)]
    [int]$Year = (Get-Date).Year,
    [string]$OutputPath = '',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$repository = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$holder = $CopyrightHolder.Trim()
if ($holder.Length -lt 2 -or $holder.Length -gt 160) {
    throw 'CopyrightHolder must contain between 2 and 160 characters.'
}
if ($holder -match '[\r\n{}<>]') {
    throw 'CopyrightHolder cannot contain line breaks or placeholder brackets.'
}

$templateName = if ($License -eq 'MIT') { 'MIT.template.txt' } else { 'PROPRIETARY.template.txt' }
$templatePath = Join-Path $repository "release\license-templates\$templateName"
if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
    throw "License template not found: $templatePath"
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $resolvedOutput = Join-Path $repository 'release\GAME_LICENSE.txt'
}
else {
    $resolvedOutput = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
}
if ((Test-Path -LiteralPath $resolvedOutput -PathType Leaf) -and -not $Force) {
    throw "License file already exists. Review it or pass -Force to replace it: $resolvedOutput"
}

$content = Get-Content -Raw -LiteralPath $templatePath
$content = $content.Replace('{{YEAR}}', $Year.ToString())
$content = $content.Replace('{{COPYRIGHT_HOLDER}}', $holder)
if ($content -match '\{\{[^}]+\}\}') {
    throw 'License generation left an unresolved template placeholder.'
}

$outputDirectory = Split-Path -Parent $resolvedOutput
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
$utf8WithoutBom = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText($resolvedOutput, $content.TrimEnd() + [Environment]::NewLine, $utf8WithoutBom)
Write-Output "[LICENSE] Generated $License project license for '$holder': $resolvedOutput"
Write-Output '[LICENSE] Review the legal text before committing or distributing a build.'
