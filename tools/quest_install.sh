#!/usr/bin/env bash
# Linux/macOS version of tools/quest_install.ps1: export the "Quest 3S" preset
# (also runs on Quest 2), install it on the headset connected over USB and
# launch it.
#
#   tools/quest_install.sh                         # export + install + launch
#   tools/quest_install.sh --skip-export           # reinstall build/drone_fpv_vr.apk
#   tools/quest_install.sh --apk path/to/game.apk  # install an APK built elsewhere
#
# Needs: Quest in developer mode, USB cable, "Allow USB debugging" accepted in
# the headset, adb (e.g. `sudo apt install adb` or Android platform-tools).
# Exporting also needs Godot 4.7.2 with Android export templates, a JDK and
# the Android SDK set in Editor Settings (see README "Quest export").
# Override tools with GODOT=... and ADB=...
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
apk="$root/build/drone_fpv_vr.apk"
package="com.dronefpvvr.game"
skip_export=0

while [ $# -gt 0 ]; do
    case "$1" in
        --skip-export) skip_export=1 ;;
        --apk) apk="$(realpath "$2")"; skip_export=1; shift ;;
        -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

find_adb() {
    if [ -n "${ADB:-}" ]; then echo "$ADB"; return; fi
    if command -v adb >/dev/null 2>&1; then command -v adb; return; fi
    for p in "$HOME/Android/Sdk/platform-tools/adb" "${ANDROID_HOME:-/nonexistent}/platform-tools/adb"; do
        if [ -x "$p" ]; then echo "$p"; return; fi
    done
    echo "adb not found: install it (sudo apt install adb) or set ADB=/path/to/adb" >&2
    exit 1
}

godot_cmd() {
    if [ -n "${GODOT:-}" ]; then echo "$GODOT"; return; fi
    for g in godot godot4; do
        if command -v "$g" >/dev/null 2>&1; then echo "$g"; return; fi
    done
    if command -v flatpak >/dev/null 2>&1 && flatpak info org.godotengine.Godot >/dev/null 2>&1; then
        echo "flatpak run --filesystem=$root --filesystem=home org.godotengine.Godot"; return
    fi
    echo "Godot not found: install Godot 4.7.2 or set GODOT=/path/to/godot" >&2
    exit 1
}

if [ "$skip_export" -eq 0 ]; then
    godot="$(godot_cmd)"
    mkdir -p "$(dirname "$apk")"
    rm -f "$apk"
    echo "Exporting APK (takes a minute)..."
    # shellcheck disable=SC2086  # $godot may be a multi-word flatpak command
    $godot --headless --path "$root" --export-debug "Quest 3S" "$apk" 2>&1 | grep -E "ERROR" || true
    [ -f "$apk" ] || { echo "Export failed: see the errors above." >&2; exit 1; }
fi

[ -f "$apk" ] || { echo "No APK at $apk" >&2; exit 1; }
adb="$(find_adb)"
"$adb" start-server >/dev/null 2>&1
devices="$("$adb" devices | tail -n +2 | grep -E '\S' || true)"
if [ -z "$devices" ]; then
    echo "No headset found. Plug in the Quest, put it on and accept 'Allow USB debugging'." >&2
    echo "Still nothing? Linux may need a udev rule, see README 'Quest from Linux'." >&2
    exit 1
fi
if echo "$devices" | grep -q unauthorized; then
    echo "Headset found but not authorised: accept 'Allow USB debugging' inside the headset." >&2
    exit 1
fi
if echo "$devices" | grep -q "no permissions"; then
    echo "No USB permission for the headset: add the udev rule from README 'Quest from Linux'." >&2
    exit 1
fi

echo "Installing $(( $(stat -c %s "$apk") / 1048576 )) MB..."
"$adb" install -r "$apk"
echo "Launching..."
"$adb" shell monkey -p "$package" -c android.intent.category.LAUNCHER 1 >/dev/null
echo "Done. Put the headset on. Logs: $adb logcat -s godot"
