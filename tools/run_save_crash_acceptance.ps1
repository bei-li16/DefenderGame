param(
    [string]$GodotConsole = 'D:\Software\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe'
)

$ErrorActionPreference = 'Stop'

$repository = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$testDirectory = Join-Path $env:APPDATA 'Godot\app_userdata\Aegis of Ember\save-crash-acceptance'
$readyMarker = Join-Path $testDirectory 'ready.marker'
$temporaryProfile = Join-Path $testDirectory 'profile.json.tmp'
$outputDirectory = Join-Path $repository 'Builds\SaveCrashTest'
$writerOutput = Join-Path $outputDirectory 'writer.stdout.log'
$writerError = Join-Path $outputDirectory 'writer.stderr.log'

if (-not (Test-Path -LiteralPath $GodotConsole -PathType Leaf)) {
    throw "Godot console executable not found: $GodotConsole"
}

New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

$writer = Start-Process `
    -FilePath $GodotConsole `
    -ArgumentList @('--headless', '--path', $repository, '--script', 'res://tests/save_crash_writer.gd') `
    -PassThru `
    -WindowStyle Hidden `
    -RedirectStandardOutput $writerOutput `
    -RedirectStandardError $writerError

$terminatedDuringWrite = $false
try {
    $readyDeadline = [DateTime]::UtcNow.AddSeconds(20)
    while (-not (Test-Path -LiteralPath $readyMarker -PathType Leaf)) {
        $writer.Refresh()
        if ($writer.HasExited) {
            throw "Crash writer exited before creating the ready marker (exit $($writer.ExitCode))."
        }
        if ([DateTime]::UtcNow -gt $readyDeadline) {
            throw 'Timed out waiting for the crash writer ready marker.'
        }
        Start-Sleep -Milliseconds 10
    }

    $writeDeadline = [DateTime]::UtcNow.AddSeconds(30)
    while ($true) {
        $writer.Refresh()
        if ($writer.HasExited) {
            throw "Crash writer completed before it could be interrupted (exit $($writer.ExitCode))."
        }
        if (Test-Path -LiteralPath $temporaryProfile -PathType Leaf) {
            $temporaryLength = (Get-Item -LiteralPath $temporaryProfile).Length
            if ($temporaryLength -ge 1MB) {
                Stop-Process -Id $writer.Id -Force
                $writer.WaitForExit()
                $terminatedDuringWrite = $true
                Write-Output "[CRASH HARNESS] terminated_pid=$($writer.Id) temporary_bytes=$temporaryLength"
                break
            }
        }
        if ([DateTime]::UtcNow -gt $writeDeadline) {
            throw 'Timed out waiting for an in-progress temporary save.'
        }
        Start-Sleep -Milliseconds 5
    }
}
finally {
    $writer.Refresh()
    if (-not $writer.HasExited) {
        Stop-Process -Id $writer.Id -Force
        $writer.WaitForExit()
    }
}

if (-not $terminatedDuringWrite) {
    throw 'The writer was not terminated during a save.'
}

& $GodotConsole --headless --path $repository --script 'res://tests/save_crash_verify.gd'
$verifyExitCode = $LASTEXITCODE
if ($verifyExitCode -ne 0) {
    throw "Crash recovery verification failed with exit code $verifyExitCode."
}

Write-Output '[CRASH HARNESS] PASS: restart recovered a valid main or backup profile.'
