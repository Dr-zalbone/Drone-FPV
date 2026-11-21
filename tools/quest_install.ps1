# Export the "Quest 3S" preset (also runs on Quest 2), install it on the
# headset connected over USB and launch it.
#
#   powershell -ExecutionPolicy Bypass -File tools\quest_install.ps1
#   powershell -ExecutionPolicy Bypass -File tools\quest_install.ps1 -SkipExport   # reinstall the last APK
#
# Needs: Quest in developer mode, USB cable, "Allow USB debugging" accepted in
# the headset. Godot / adb paths default to the Steam Godot and the Android
# Studio SDK; override with -Godot / -Adb.
param(
    [switch]$SkipExport,
    [string]$Godot = "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe",
    [string]$Adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$apk = Join-Path $root "build\drone_fpv_vr.apk"
$package = "com.dronefpvvr.game"

if (-not $SkipExport) {
    New-Item -ItemType Directory -Force (Split-Path $apk) | Out-Null
    Remove-Item $apk -ErrorAction SilentlyContinue
    Write-Host "Exporting APK (takes a minute)..."
    # Godot writes errors to stderr; with "Stop", PowerShell 5 would abort on
    # the first stderr line before the reason (the next line) is printed.
    $ErrorActionPreference = "Continue"
    $log = & $Godot --headless --path $root --export-debug "Quest 3S" $apk 2>&1 | ForEach-Object { "$_" }
    $ErrorActionPreference = "Stop"
    # Print each ERROR line plus the line after it (the configuration reason).
    for ($i = 0; $i -lt $log.Count; $i++) {
        if ($log[$i] -match "ERROR") {
            Write-Host $log[$i] -ForegroundColor Red
            if ($i + 1 -lt $log.Count -and $log[$i + 1] -notmatch "^\s*at:") { Write-Host $log[$i + 1] -ForegroundColor Red }
        }
    }
    if (-not (Test-Path $apk)) { throw "Export failed: see the errors above. Missing Java/Android SDK path? Editor -> Editor Settings -> Export -> Android." }
}

# Start the adb server detached: started from a pipeline, the server inherits
# the pipe and the shell waits on it forever.
Start-Process -FilePath $Adb -ArgumentList "start-server" -WindowStyle Hidden -Wait
$devices = & $Adb devices | Select-Object -Skip 1 | Where-Object { $_ -match "\S" }
if (-not $devices) { throw "No headset found. Plug in the Quest, put it on and accept 'Allow USB debugging'." }
if ($devices -match "unauthorized") { throw "Headset found but not authorised: accept 'Allow USB debugging' inside the headset." }

Write-Host "Installing $([math]::Round((Get-Item $apk).Length / 1MB)) MB..."
& $Adb install -r $apk
if ($LASTEXITCODE -ne 0) { throw "adb install failed." }
Write-Host "Launching..."
& $Adb shell monkey -p $package -c android.intent.category.LAUNCHER 1 | Out-Null
Write-Host "Done. Put the headset on. Logs: & '$Adb' logcat -s godot"
