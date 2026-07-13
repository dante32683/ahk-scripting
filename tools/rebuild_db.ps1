# rebuild_db.ps1
# Script to reconstruct Autocorrect_Database.txt from the generated lib/Autocorrect.ahk

$ahkPath = Join-Path $PSScriptRoot "..\lib\Autocorrect.ahk"
$dbPath = Join-Path $PSScriptRoot "..\Autocorrect_Database.txt"

if (-not (Test-Path $ahkPath)) {
    Write-Error "Could not find Autocorrect.ahk at $ahkPath"
    exit 1
}

Write-Host "Reading $ahkPath..."
$content = Get-Content -Path $ahkPath -Encoding UTF8 -Raw

Write-Host "Extracting autocorrect entries..."
# Match lines like: :CX:trigger::AC_Proc("trigger", "correction", ...)
# Triggers and corrections can contain escaped double quotes (e.g. `")
$pattern = '(?m)^\s*:CX:.*?::AC_Proc\("(?<trigger>.*?)",\s*"(?<correction>.*?)"'
$matches = [regex]::Matches($content, $pattern)

$entries = New-Object System.Collections.Generic.List[string]

foreach ($match in $matches) {
    $trigger = $match.Groups['trigger'].Value
    $correction = $match.Groups['correction'].Value

    # Replace backtick-escaped quotes (`") with regular double quotes (")
    $trigger = $trigger -replace '`"', '"'
    $correction = $correction -replace '`"', '"'

    if ($trigger -ne "" -and $correction -ne "") {
        $entries.Add("$trigger->$correction")
    }
}

Write-Host "Found $($entries.Count) entries. Sorting alphabetically..."
# Case-insensitive sort
$sortedEntries = $entries | Sort-Object

Write-Host "Writing to $dbPath..."
# Write to Autocorrect_Database.txt in UTF-8
$sortedEntries | Out-File -FilePath $dbPath -Encoding utf8

Write-Host "Autocorrect database recovered successfully with $($sortedEntries.Count) entries."
