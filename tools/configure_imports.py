"""Patch Godot .import files for processed assets (run between two
`godot --import` passes by tools/process_models.sh).

* assets/maps/*.glb  -> post-import script, auto LOD on/off per manifest
* assets/maps images -> VRAM compressed, high quality (ASTC 4x4 on Quest,
  BPTC on PC). Lossless would sit in VRAM as raw RGBA8: 4x the memory and
  bandwidth of ASTC 4x4, which matters on a mobile GPU. Mipmaps kept for VR
  shimmer control.
Returns exit code 0; prints what changed.
"""
import glob
import os
import re
import sys

ROOT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.getcwd())


def set_param(text, key, value):
    line = f"{key}={value}"
    pattern = re.compile(rf"^{re.escape(key)}=.*$", re.MULTILINE)
    if pattern.search(text):
        return pattern.sub(line, text)
    return text.replace("[params]\n", f"[params]\n\n{line}\n", 1) if "[params]" in text else text + f"\n[params]\n\n{line}\n"


def patch(path, params):
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    new = text
    for key, value in params.items():
        new = set_param(new, key, value)
    if new != text:
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(new)
        print(f"patched {os.path.relpath(path, ROOT)}")
        return True
    return False


def main():
    changed = False
    for imp in glob.glob(os.path.join(ROOT, "assets", "maps", "*.glb.import")):
        changed |= patch(imp, {
            "import_script/path": '"res://tools/map_post_import.gd"',
            # Maps carry their own per-chunk LOD meshes (see process_models.py);
            # Godot's auto-LOD cannot simplify photo-atlas meshes anyway.
            "meshes/generate_lods": "false",
            "meshes/create_shadow_meshes": "false",
            "meshes/light_baking": "0",
        })
    for ext in ("png", "jpg", "jpeg", "webp"):
        for imp in glob.glob(os.path.join(ROOT, "assets", "maps", f"*.{ext}.import")):
            changed |= patch(imp, {
                "compress/mode": "2",
                "compress/high_quality": "true",
                "detect_3d/compress_to": "0",
                "mipmaps/generate": "true",
            })
    print("configure_imports: " + ("changes made" if changed else "nothing to change"))


if __name__ == "__main__":
    main()
