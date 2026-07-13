# tools/check.ps1
param(
    [string]$AhkExe = ""
)

$ErrorActionPreference = "Stop"

# 1. Locate AutoHotkey64.exe
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

# Set test mode environment variable
$env:AHK_TEST_MODE = "1"
$failed = $false

function Run-AhkScript {
    param(
        [string]$ScriptPath
    )
    Write-Host "Checking script: $ScriptPath..."
    
    $tmpOut = [System.IO.Path]::GetTempFileName()
    $tmpErr = [System.IO.Path]::GetTempFileName()
    
    try {
        $proc = Start-Process -FilePath $AhkExe -ArgumentList "/ErrorStdOut", "`"$ScriptPath`"" -NoNewWindow -PassThru -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr
        
        # Wait up to 15 seconds for completion
        $terminated = $false
        if (-not $proc.WaitForExit(15000)) {
            $proc | Stop-Process -Force
            $terminated = $true
        }
        
        $exitCode = $proc.ExitCode
        $stdout = Get-Content -Path $tmpOut -Raw -Encoding UTF8
        $stderr = Get-Content -Path $tmpErr -Raw -Encoding UTF8
        
        if ($terminated) {
            Write-Error "Script execution timed out (hung): $ScriptPath"
            $global:failed = $true
            return $false
        }
        
        if ($exitCode -ne 0) {
            Write-Error "Script exited with non-zero code ($exitCode): $ScriptPath"
            if ($stdout) { Write-Host "Stdout:`n$stdout" -ForegroundColor Red }
            if ($stderr) { Write-Host "Stderr:`n$stderr" -ForegroundColor Red }
            $global:failed = $true
            return $false
        }
        
        if ($stderr -and $stderr.Trim() -ne "") {
            Write-Error "Script generated stderr output: $ScriptPath"
            Write-Host "Stderr:`n$stderr" -ForegroundColor Red
            $global:failed = $true
            return $false
        }
        
        Write-Host "Success: $ScriptPath parsed and initialized cleanly." -ForegroundColor Green
        return $true
    }
    finally {
        if (Test-Path $tmpOut) { Remove-Item $tmpOut -Force }
        if (Test-Path $tmpErr) { Remove-Item $tmpErr -Force }
    }
}

# 2. Run both entry points
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$masterPath = Join-Path $repoRoot "Master.ahk"
$masterPcPath = Join-Path $repoRoot "Master-PC.ahk"

$masterOk = Run-AhkScript -ScriptPath $masterPath
$masterPcOk = Run-AhkScript -ScriptPath $masterPcPath

# 3. Run every test file under tests/ (if tests/ folder exists and contains files)
$testsDir = Join-Path $repoRoot "tests"
if (Test-Path $testsDir) {
    $testFiles = Get-ChildItem -Path $testsDir -Filter "test_*.ahk" -Recurse
    foreach ($file in $testFiles) {
        Run-AhkScript -ScriptPath $file.FullName
    }
}

# 4. Run the autocorrect database validator (to be implemented in later phases, or run if exists)
# For now, we will add a simple check in check.ps1 itself or placeholder.

if ($failed) {
    Write-Host "Checks FAILED." -ForegroundColor Red
    exit 1
} else {
    Write-Host "All checks passed successfully." -ForegroundColor Green
    exit 0
}
