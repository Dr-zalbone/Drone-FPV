#!/usr/bin/env bash
# Transcode every attributed source model in the project root into
# Quest-ready assets under assets/, then re-import them in Godot.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

BLENDER="${BLENDER:-}"
if [[ -z "$BLENDER" ]]; then
  if command -v blender >/dev/null; then BLENDER="blender"
  else BLENDER="flatpak run --filesystem=$ROOT org.blender.Blender"; fi
fi
GODOT="${GODOT:-}"
if [[ -z "$GODOT" ]]; then
  if command -v godot >/dev/null; then GODOT="godot"
  else GODOT="flatpak run --filesystem=$ROOT org.godotengine.Godot"; fi
fi

# Usage: tools/process_models.sh [name-filter]   (filter = reprocess only matching files)
$BLENDER --background --factory-startup --python "$ROOT/tools/process_models.py" -- "$ROOT" "$@"
# First pass creates .import files, then we patch them (lossless map
# textures, LOD + post-import script) and import again.
$GODOT --headless --path "$ROOT" --import
python3 "$ROOT/tools/configure_imports.py" "$ROOT"
$GODOT --headless --path "$ROOT" --import
