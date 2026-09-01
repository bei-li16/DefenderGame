param(
    [string]$GodotExecutable = 'D:\Software\Godot-4.7.2\Godot_v4.7.2-stable_win64.exe',
    [int]$StartupSamples = 5
)

$ErrorActionPreference = 'Stop'

$repository = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$outputDirectory = Join-Path $repository 'Builds\RuntimeProbe'
$runtimeOutput = Join-Path $outputDirectory 'stdout.log'
$runtimeError = Join-Path $outputDirectory 'stderr.log'

if (-not (Test-Path -LiteralPath $GodotExecutable -PathType Leaf)) {
    throw "Godot executable not found: $GodotExecutable"
}
if ($StartupSamples -lt 1) {
    throw 'StartupSamples must be at least 1.'
}

New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

$runtime = Start-Process `
    -FilePath $GodotExecutable `
    -ArgumentList @('--path', $repository, '--script', 'res://tests/runtime_probe.gd') `
    -PassThru `
    -WindowStyle Hidden `
    -RedirectStandardOutput $runtimeOutput `
    -RedirectStandardError $runtimeError

$peakWorkingSet = 0L
while (-not $runtime.HasExited) {
    $runtime.Refresh()
    if ($runtime.WorkingSet64 -gt $peakWorkingSet) {
        $peakWorkingSet = $runtime.WorkingSet64
    }
    Start-Sleep -Milliseconds 50
}
$runtime.WaitForExit()

$runtimeStdout = if (Test-Path -LiteralPath $runtimeOutput) { Get-Content -LiteralPath $runtimeOutput -Raw } else { '' }
$runtimeStderr = if (Test-Path -LiteralPath $runtimeError) { Get-Content -LiteralPath $runtimeError -Raw } else { '' }
$peakWorkingSetMiB = [math]::Round($peakWorkingSet / 1MB, 2)
Write-Output "[PROCESS] exit=$($runtime.ExitCode) peak_working_set_mib=$peakWorkingSetMiB"
Write-Output $runtimeStdout
if ($runtimeStderr) {
    Write-Output "[STDERR]`n$runtimeStderr"
}
if ($runtime.ExitCode -ne 0) {
    throw "Runtime probe failed with exit code $($runtime.ExitCode)."
}
if ($peakWorkingSet -ge 750MB) {
    throw "Runtime peak working set exceeded 750 MiB: $peakWorkingSetMiB MiB."
}

$startupTimes = @()
for ($sample = 1; $sample -le $StartupSamples; $sample++) {
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $process = Start-Process `
        -FilePath $GodotExecutable `
        -ArgumentList @('--path', $repository, '--quit-after', '2') `
        -PassThru `
        -WindowStyle Hidden
    $process.WaitForExit()
    $stopwatch.Stop()
    if ($process.ExitCode -ne 0) {
        throw "Startup sample $sample exited with code $($process.ExitCode)."
    }
    $startupTimes += $stopwatch.Elapsed.TotalSeconds
    Write-Output "[STARTUP] sample=$sample elapsed_s=$([math]::Round($stopwatch.Elapsed.TotalSeconds, 3))"
}

$sortedTimes = $startupTimes | Sort-Object
$average = ($startupTimes | Measure-Object -Average).Average
$p95Index = [math]::Ceiling($sortedTimes.Count * 0.95) - 1
$p95 = $sortedTimes[$p95Index]
$maximum = $sortedTimes[-1]
Write-Output "[STARTUP] average_s=$([math]::Round($average, 3)) p95_s=$([math]::Round($p95, 3)) max_s=$([math]::Round($maximum, 3)) target_s=4"
if ($maximum -ge 4.0) {
    throw "Startup target exceeded: $([math]::Round($maximum, 3)) seconds."
}

Write-Output '[WINDOWS RUNTIME] PASS: frame, renderer, memory and startup gates passed.'
