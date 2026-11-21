#!/usr/bin/env bash
# Transcode every attributed source model in the project root into
# Quest-ready assets under assets/, then re-import them in Godot.
# Works on Linux (flatpak or PATH) and Windows (Git Bash, default install paths).
# Override the tools with BLENDER=..., GODOT=..., PYTHON=... if needed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

first_existing() {
  for p in "$@"; do
    if [[ -x "$p" ]]; then echo "$p"; return 0; fi
  done
  return 1
}

if [[ -z "${BLENDER:-}" ]]; then
  if command -v blender >/dev/null; then BLENDER="blender"
  elif BLENDER="$(first_existing /c/Program\ Files/Blender\ Foundation/Blender*/blender.exe)"; then :
  else BLENDER="flatpak run --filesystem=$ROOT org.blender.Blender"; fi
fi
if [[ -z "${GODOT:-}" ]]; then
  if command -v godot >/dev/null; then GODOT="godot"
  elif GODOT="$(first_existing \
      "/c/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" \
      /c/Program\ Files/Godot*/Godot*.exe)"; then :
  else GODOT="flatpak run --filesystem=$ROOT org.godotengine.Godot"; fi
fi
if [[ -z "${PYTHON:-}" ]]; then
  # On Windows "python3" is often the Microsoft Store stub; prefer the py launcher.
  if command -v py >/dev/null; then PYTHON="py -3"
  else PYTHON="python3"; fi
fi

run() { if [[ "$1" == *" "* && -x "$1" ]]; then "$@"; else eval "$1" '"${@:2}"'; fi; }

# Usage: tools/process_models.sh [name-filter]   (filter = reprocess only matching files)
run "$BLENDER" --background --factory-startup --python "$ROOT/tools/process_models.py" -- "$ROOT" "$@"
# First pass creates .import files, then we patch them (VRAM-compressed map
# textures, LOD + post-import script) and import again.
run "$GODOT" --headless --path "$ROOT" --import
run "$PYTHON" "$ROOT/tools/configure_imports.py" "$ROOT"
run "$GODOT" --headless --path "$ROOT" --import
