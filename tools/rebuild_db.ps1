# tools/rebuild_db.ps1
# The database Autocorrect_Database.txt is the source of truth.
# Regenerating the database from Autocorrect.ahk is intentionally unsupported.
# To rebuild generated hotstrings, edit Autocorrect_Database.txt and reload the script
# (or run BuildAutocorrect via AutoHotkey).

Write-Host "rebuild_db.ps1: Autocorrect_Database.txt is the source of truth."
Write-Host "Edit the database and reload Master.ahk / Master-PC.ahk to regenerate lib/Autocorrect.ahk."
Write-Host "To validate: .\tools\check.ps1"
exit 0
