# tools/check.ps1
param(
    [string]$AhkExe = ""
)

$ErrorActionPreference = "Stop"

if ($AhkExe -eq "") {
    $searchPaths = @(
        "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe",
        "C:\Program Files\AutoHotkey\v2\AutoHotkey.exe",
        "C:\Program Files\AutoHotkey\AutoHotkey64.exe",
        "C:\Program Files\AutoHotkey\AutoHotkey.exe"
    )
    foreach ($path in $searchPaths) {
        if (Test-Path $path) {
            $AhkExe = $path
            break
        }
    }
}

if ($AhkExe -eq "" -or -not (Test-Path $AhkExe)) {
    Write-Error "Could not locate AutoHotkey64.exe. Please pass it using -AhkExe."
    exit 1
}

Write-Host "Using AutoHotkey: $AhkExe"

$env:AHK_TEST_MODE = "1"
$script:failed = $false

# The boot tests declare `#SingleInstance Off` and run in CFG_TestMode (no hooks,
# no shared-file locks, immediate exit), so an isolated test run must never touch a
# live Master instance. Do NOT force-kill the user's running script here.

function Run-AhkScript {
    param(
        [string]$ScriptPath
    )
    Write-Host "Checking script: $ScriptPath..."

    $tmpOut = [System.IO.Path]::GetTempFileName()
    $tmpErr = [System.IO.Path]::GetTempFileName()

    try {
        $proc = Start-Process -FilePath $AhkExe -ArgumentList "/ErrorStdOut", "`"$ScriptPath`"" -NoNewWindow -PassThru -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr

        $terminated = $false
        if (-not $proc.WaitForExit(90000)) {
            $proc | Stop-Process -Force
            $terminated = $true
        }

        $exitCode = $proc.ExitCode
        $stdout = Get-Content -Path $tmpOut -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        $stderr = Get-Content -Path $tmpErr -Raw -Encoding UTF8 -ErrorAction SilentlyContinue

        if ($terminated) {
            Write-Host "Script execution timed out (hung): $ScriptPath" -ForegroundColor Red
            $script:failed = $true
            return $false
        }

        if ($exitCode -ne 0) {
            Write-Host "Script exited with non-zero code ($exitCode): $ScriptPath" -ForegroundColor Red
            if ($stdout) { Write-Host "Stdout:`n$stdout" -ForegroundColor Red }
            if ($stderr) { Write-Host "Stderr:`n$stderr" -ForegroundColor Red }
            $script:failed = $true
            return $false
        }

        if ($stderr -and $stderr.Trim() -ne "") {
            Write-Host "Script generated stderr output: $ScriptPath" -ForegroundColor Red
            Write-Host "Stderr:`n$stderr" -ForegroundColor Red
            $script:failed = $true
            return $false
        }

        Write-Host "Success: $ScriptPath" -ForegroundColor Green
        return $true
    }
    finally {
        if (Test-Path $tmpOut) { Remove-Item $tmpOut -Force }
        if (Test-Path $tmpErr) { Remove-Item $tmpErr -Force }
    }
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

# Prefer dedicated SingleInstance-Off boot tests so a live Master.ahk is not killed.
$bootLaptop = Join-Path $repoRoot "tests\test_boot_laptop.ahk"
$bootDesktop = Join-Path $repoRoot "tests\test_boot_desktop.ahk"
if (Test-Path $bootLaptop) {
    Run-AhkScript -ScriptPath $bootLaptop | Out-Null
} else {
    Run-AhkScript -ScriptPath (Join-Path $repoRoot "Master.ahk") | Out-Null
}
if (Test-Path $bootDesktop) {
    Run-AhkScript -ScriptPath $bootDesktop | Out-Null
} else {
    Run-AhkScript -ScriptPath (Join-Path $repoRoot "Master-PC.ahk") | Out-Null
}

$testsDir = Join-Path $repoRoot "tests"
if (Test-Path $testsDir) {
    $testFiles = Get-ChildItem -Path $testsDir -Filter "test_*.ahk" -Recurse |
        Where-Object { $_.Name -notmatch '^test_boot_' }
    foreach ($file in $testFiles) {
        Run-AhkScript -ScriptPath $file.FullName | Out-Null
    }
}

# Autocorrect database validator
$validateScript = Join-Path $testsDir "validate_autocorrect.ahk"
if (Test-Path $validateScript) {
    Run-AhkScript -ScriptPath $validateScript | Out-Null
}

if ($script:failed) {
    Write-Host "Checks FAILED." -ForegroundColor Red
    exit 1
} else {
    Write-Host "All checks passed successfully." -ForegroundColor Green
    exit 0
}
