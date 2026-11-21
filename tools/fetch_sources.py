#!/usr/bin/env python3
"""Download the raw Sketchfab source models listed in tools/sources.json.

Raw sources are not stored in git (they are large and can be re-downloaded).
Each lands in the project root as a folder named after its attribution stem
(<title>_attribution-<author>_on_sketchfab/scene.gltf + textures), with a
.gdignore so Godot skips it, ready for tools/process_models.sh.

Needs a Sketchfab API token (free accounts work) in the SKETCHFAB_API_TOKEN
environment variable: sketchfab.com -> Settings -> Password & API.

    python tools/fetch_sources.py              # fetch every missing source
    python tools/fetch_sources.py cathedral    # only entries whose file name matches
    python tools/fetch_sources.py --check      # verify token + download links only
"""
import json
import os
import pathlib
import sys
import tempfile
import urllib.request
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
API = "https://api.sketchfab.com/v3/models/{uid}/download"


def token() -> str:
    tok = os.environ.get("SKETCHFAB_API_TOKEN", "")
    if not tok and sys.platform == "win32":
        # A user env var set after this shell started is still in the registry.
        import winreg
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as key:
                tok = winreg.QueryValueEx(key, "SKETCHFAB_API_TOKEN")[0]
        except OSError:
            tok = ""
    if not tok:
        sys.exit("SKETCHFAB_API_TOKEN is not set (sketchfab.com -> Settings -> Password & API).")
    return tok


def download_links(uid: str, tok: str) -> dict:
    req = urllib.request.Request(API.format(uid=uid), headers={"Authorization": f"Token {tok}"})
    with urllib.request.urlopen(req) as resp:
        return json.load(resp)


def fetch(url: str, dest: pathlib.Path) -> None:
    with urllib.request.urlopen(url) as resp, open(dest, "wb") as out:
        while chunk := resp.read(1 << 20):
            out.write(chunk)


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    check_only = "--check" in sys.argv
    tok = token()
    entries = json.loads((ROOT / "tools" / "sources.json").read_text(encoding="utf-8"))
    for e in entries:
        if args and not any(a.lower() in e["file"].lower() for a in args):
            continue
        dest = ROOT / e["file"]
        links = download_links(e["uid"], tok)
        kinds = ", ".join(sorted(links))
        if check_only:
            print(f"ok   {e['file']}  (formats: {kinds})")
            continue
        # The glTF zip carries the ORIGINAL textures (e.g. 4096 px); Sketchfab's
        # "glb" download is a downscaled 1024 px version. Prefer the zip and
        # keep it as a folder named after the attribution stem.
        folder = dest.with_suffix("")
        if folder.is_dir() or dest.exists():
            print(f"skip {e['file']} (already present)")
            continue
        if "gltf" in links:
            print(f"get  {folder.name}/ (gltf zip, {links['gltf'].get('size', 0) >> 20} MB)")
            with tempfile.TemporaryDirectory() as tmp:
                zpath = pathlib.Path(tmp) / "model.zip"
                fetch(links["gltf"]["url"], zpath)
                with zipfile.ZipFile(zpath) as z:
                    z.extractall(folder)
            # Godot must not import the raw source (slow, and it would ship in the APK).
            (folder / ".gdignore").write_text("", encoding="utf-8")
        elif "glb" in links:
            print(f"get  {e['file']} (glb, {links['glb'].get('size', 0) >> 20} MB)")
            fetch(links["glb"]["url"], dest)
        else:
            print(f"FAIL {e['file']}: no glb/gltf download (formats: {kinds})")


if __name__ == "__main__":
    main()
