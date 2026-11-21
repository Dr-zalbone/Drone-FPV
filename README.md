# Drone FPV VR (Godot 4.7, Meta Quest 3S)

VR drone simulator. You can fly a DJI Mini 5 Pro, a DJI FPV or a DJI FlyCart 30 in
imported Sketchfab worlds. Every view gives a full 360° look-around.

## Views

| View | Who can use it | Head movement |
|---|---|---|
| **FPV (goggles)** | all drones | **Looking steers the drone** (DJI goggles head-tracking style): look left/right and the drone turns to face there; look up/down to tilt the camera. The yaw stick turns view and drone together. In Manual (acro) mode the view simply turns with the drone. |
| **3rd person** | all drones | Turning your head **orbits** the camera around the drone. The default view is **world-fixed**. |
| **Flyer (pilot)** | Mini 5 Pro, FlyCart | You stand still as the pilot. Your body turns only on yaw with your head, and the RC is held at chest height, so looking down always shows its live drone-camera screen and telemetry. |

Press **X** (or **L**) to switch the 3rd person view between "turns with drone" and "world-fixed".
In the pause menu, you can also turn on "FPV horizon tilts with drone" (real goggles feel, harder on the stomach).

## Flight modes

| Drone | Modes | Character |
|---|---|---|
| DJI Mini 5 Pro (249 g) | Cine / Normal / Sport | Very steady and smooth, made for cinematic shots |
| DJI FPV (795 g) | Normal / Sport / **Manual** | Fast and agile. Manual is full acro mode (rate control, no self-levelling) |
| DJI FlyCart 30 (~65 kg) | Normal / Sport | Heavy, slow and sluggish |

In Manual mode the centred throttle stick means **hover thrust**, because Quest sticks spring back to centre.

## Controls (Mode 2)

| Quest | Desktop | Action |
|---|---|---|
| Left stick | W/S, A/D or gamepad left stick | Throttle / yaw |
| Right stick | Arrow keys or gamepad right stick | Pitch / roll |
| A | M | Next flight mode |
| B | R | Reset the drone |
| Y | V | Next view |
| X | L | Toggle view lock (turns with drone / world-fixed) |
| Right grip | Middle mouse button | Recenter the view |
| Menu (left) | Esc | Pause menu |
| Right trigger | Left mouse button | Click on menus |

When no OpenXR runtime is found, the game runs in desktop mode with mouse look.
OpenXR is switched off for Windows runs (`xr/openxr/enabled.windows=false` in `project.godot`), so testing on the PC without a headset shows no popup. Delete that line to use PC VR (Quest Link). Quest/Android builds are not affected.

## Maps

| Map | Source | Licence |
|---|---|---|
| Cathedral | [patrix on Sketchfab](https://sketchfab.com/3d-models/faed84a829114e378be255414a7826ca) | CC BY-SA 4.0 |
| Èze Village - France | [Azad Balabanian on Sketchfab](https://sketchfab.com/3d-models/a18a1449661643e6ab98640a3e7eafc1) | CC BY 4.0 |
| Lakeside - Exterior Scene | [aurelien_martel on Sketchfab](https://sketchfab.com/3d-models/07dfe01fb78c441db081646ff4c1d9e0) | CC BY 4.0 |
| New York City. Manhattan | [truekit on Sketchfab](https://sketchfab.com/3d-models/372bc495b3a941308f4a3198bc45e17b) | CC BY 4.0 |
| Osaka downtown (night) | [matousekfoto on Sketchfab](https://sketchfab.com/3d-models/53e0980d555a4af6b921cc00c208e4a3) | CC BY 4.0 |
| Leipzig industrial area | [333DDD on Sketchfab](https://sketchfab.com/3d-models/0f7a50194345495984458bb4c5e562ba) | CC BY 4.0 |
| Castle of Loarre | [matousekfoto on Sketchfab](https://sketchfab.com/3d-models/2876fc98a198429ca34ea7f0a2dae014) | Sketchfab Free Standard |
| Valley Town (built-in) | generated in code (`scripts/world/test_field.gd`) | — |

The pilot starts on a **lookout**: a raised, flat spot with a wide view near the middle of the map, facing into the map, with flat ground for the drone close by (`WorldBuilder.find_pilot_spawn`). Dioramas such as the Cathedral set `spawn_low` instead: the pilot stands on the diorama's ground, facing the building.

The Cathedral's lighting is baked into its **emissive** texture (it has no base colour). With `unshaded`, `MapDressing` uses that texture as the colour, as Sketchfab shows it; lit, it would render almost white.
Maps with `surround` in their manifest entry get a sea or ground plane out to the horizon, so there is no grey void past the scanned area (`MapDressing`).

## Adding models

Raw source models are **not in git**. They are large, and they can be downloaded again.
`tools/sources.json` lists each model's Sketchfab ID, author and licence. To download them all:

1. Get a Sketchfab API token (free accounts work): sketchfab.com → Settings → Password & API.
2. Store it as a user environment variable named `SKETCHFAB_API_TOKEN`.
3. Run `python tools/fetch_sources.py` (or `py tools/fetch_sources.py` on Windows).

The script downloads Sketchfab's **glTF zip**, because it holds the original textures (for example 4096 px).
Sketchfab's "glb" download is a downscaled 1024 px version, so do not use it for maps.
Each model lands in a root folder named after its attribution, with a `.gdignore` so Godot skips it.

To add a new model, add an entry to `tools/sources.json` and run the fetch script.
You can also drop a file in the project root. The file or folder name must carry the attribution:

```
<title>_attribution-<author>_on_<site>.glb      (.gltf / .fbx / .obj also work, or a folder holding a .gltf)
```

- Names containing `flycart`, `mini` or `fpv` are drones. They replace the built-in placeholder for that drone.
- Names containing `pilot`, `flyer`, `person` or `human` are the pilot figure.
- Every other model is a world (map).

Then run the pipeline. It needs Blender and Godot. It finds them on the PATH, as Linux flatpaks, or in the default Windows install folders (Blender Foundation, Steam). Override them with `BLENDER=`, `GODOT=` or `PYTHON=`.

```bash
tools/process_models.sh            # on Windows, run it from Git Bash
```

The pipeline does the following:
- Keeps map visuals at the **original** geometry. Map textures are capped at 4096 px and stored as WebP (quality 90) to keep the repo small. Godot re-compresses them to VRAM formats (ASTC 4×4 on Quest) on import anyway.
- Splits each map into spatial chunks: 48–190 m cells, or 12 m for the cathedral.
- Gives each chunk LOD0 (the original), LOD1 (50 %) and LOD2 (20 %).
- Builds a merged collision mesh of up to 60k triangles. The mesh name ends in `-colonly`, so Godot imports it as a trimesh `StaticBody3D`.
- Writes `assets/maps/*.glb`, `assets/drones/*.glb`, `assets/pilot/pilot.glb`, `assets/maps/manifest.json` and `assets/credits.json`, with each model's licence from `tools/sources.json`.

The credits panel on the start screen reads `credits.json`.
Processed assets under `assets/` are stored with **Git LFS**. Run `git lfs install` once per machine.

To reprocess only one model, pass part of its file name: `tools/process_models.sh cathedral`.

Per-map tuning lives in `MAP_OVERRIDES` in `tools/process_models.py`:

| Map | Override | Why |
|---|---|---|
| Eze Village | `scale 0.01`, skybox mesh dropped, `unshaded`, `surround: sea` | The photogrammetry is authored about 100× too large, and its lighting is baked into the photos. Èze is on the coast. |
| New York City Manhattan | `scale 250`, `facade_detail`, `surround: sea` | The source is an 8 × 11 m miniature. Manhattan is an island. |
| Cathedral | 12 m chunks, no LOD1/LOD2, `visual_dissolve`, collision voxel-remeshed at 0.35 m | It is voxel art: decimation shatters the cubes, but merging flat runs of same-coloured faces is lossless. |
| Lakeside | `surround: sea`, skydome mesh dropped | An island in a square lake: open water past the lake's edge hides the square. |
| Osaka downtown | `scale 12`, `night`, `visual_tris 350k` | A night scan authored as a ~50 m miniature; `night` switches the sky, fog and sun to night. |
| Leipzig / Castle of Loarre | `visual_tris 350k / 450k` | Dense scans of small areas, where distance LODs never kick in. |

All photogrammetry maps also set `unshaded` (the light is baked into the photos) and a `surround` plane.

Other override keys:
- `spawn: [x, y, z]`: fixed pilot position instead of the lookout search.
- `chunk_size`, `lods`, `visual_tris`, `collision_collapse`, `collision_voxel`.

## LOD and graphics quality

Choose **Graphics** in the menu or the pause menu.

| Preset | LOD switch distance | View distance | MSAA | Render scale |
|---|---|---|---|---|
| Low (Quest 2) | ×0.6 | 700 m | off | 0.8 |
| Medium (Quest 3S) | ×1.0 (LOD1 from 250 m+, LOD2 from 625 m+) | 1500 m | 2× | 1.0 |
| High (PC VR) | ×2.0 | 4000 m | 4× | 1.0 |

`MapLod` swaps the chunk LODs by distance using visibility ranges. Depth fog hides the view-distance cut-off.
`tests/lod_stats.gd` prints rendered triangles per preset. With the Medium preset, Manhattan renders about 95k triangles in a typical view, against 337k in the full map.

Note on Manhattan: its source has one 4096×4096 photo atlas for the whole city, about 0.5 texture pixels per metre.
To make up for it, the map turns on `facade_detail`.
- `shaders/facade_detail.gdshader` keeps the photo texture as the base colour.
- It draws a procedural window grid on vertical walls: 3.6 m storeys and 3.2 m bays, varied per facade.
- The grid fades out between 120 and 450 m.

To enable it on another low-resolution map, add `"facade_detail": True` to that map's entry in `MAP_OVERRIDES`.

## Quest export (Quest 3S and Quest 2)

One APK runs on both headsets (OpenXR, arm64). On a Quest 2, pick **Graphics: Low (Quest 2)** in the menu.

The Quest needs an OpenXR **loader** inside the APK. It comes from the *Godot OpenXR Vendors* plugin (`addons/godotopenxrvendors`, v5.2.0, binaries in Git LFS), and the plugin needs a **Gradle build**. That is why the preset sets `use_gradle_build` and `enable_meta_plugin`. Without them the game starts in the headset as a flat window: "OpenXR loader not found".

Editor setup (done once per PC):
1. Install the Godot 4.7.2 Android export templates (Editor → Manage Export Templates).
2. Editor Settings → Export → Android: set the **Android SDK path** (Android Studio: `%LOCALAPPDATA%\Android\Sdk`) and the **Java SDK path** to a **JDK 17**. Gradle 8.11 cannot run on newer JDKs such as 26.
3. The debug keystore at that same settings page must exist. Godot creates it when a JDK is set, or create it with `keytool`.
4. The Android build template (`android/`, git-ignored) is created by the install scripts, or by Project → Install Android Build Template. The first Gradle build downloads Gradle and its libraries, so it takes several minutes.

Headset setup (done once):
1. Create a free Meta developer organisation at developers.meta.com (Meta asks for this before allowing developer mode).
2. In the Meta Horizon phone app: Devices → your headset → Headset settings → **Developer mode** on.
3. Connect the headset by USB, put it on, and accept **Allow USB debugging** (tick "Always allow").

Build, install and launch:

```powershell
powershell -ExecutionPolicy Bypass -File tools\quest_install.ps1
```

Or in the editor: Project → Export → Quest 3S → Export Project, then `adb install -r build\drone_fpv_vr.apk`.
In the headset the game is under Library → **Unknown Sources**.

### Quest from Linux

```bash
git pull && git lfs pull          # once per machine before that: git lfs install
tools/quest_install.sh            # export + install + launch
tools/quest_install.sh --apk ~/Downloads/drone_fpv_vr.apk   # install an APK built on another PC
```

- Installing only needs `adb` (`sudo apt install adb`). Exporting also needs the Godot editor setup above, done on the laptop.
- If `adb devices` shows `no permissions`, add a udev rule for Meta's USB vendor ID, then replug:
  ```bash
  echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="2833", MODE="0666"' | sudo tee /etc/udev/rules.d/51-quest.rules
  sudo udevadm control --reload-rules && sudo udevadm trigger
  ```
- With the Godot flatpak, the Android SDK and JDK must be inside folders the flatpak can see (the script grants it your home folder).

### PC VR testing (Quest Link)

Windows runs skip VR by default. To test in the headset through Quest Link: start Link in the headset, then in Godot set **Debug → Customize Run Instances → Main Run Args** to `--xr-mode on --rendering-driver vulkan` and press Play.

Performance settings: the Mobile renderer, 2× MSAA, dynamic foveation, no realtime shadows, auto mesh LODs, and a 90 Hz refresh/physics rate with physics interpolation.
Photogrammetry maps with `unshaded` skip real-time lighting.
The RC screen viewport renders only in Flyer view. The RC sits on its own render layer (`rc_controller`), which the drone camera never draws: the screen shows that camera's image, so seeing it would be a feedback loop.

## Tests

```bash
flatpak run --filesystem=$PWD org.godotengine.Godot --headless --path . --script res://tests/run_tests.gd
```

```bash
flatpak run --filesystem=$PWD org.godotengine.Godot --headless --path . --script res://tests/smoke_main.gd
```

- `run_tests.gd` holds the unit tests (flight math, attribution parsing, drone catalog, view rules) and a physics integration test.
- `smoke_main.gd` loads every map with every drone, cycles all views, pauses, resets and returns to the menu.
- `screenshot_maps.gd` needs a window (no `--headless`). It saves `shot_<map>_<view>.png` and `shot_<map>_rc.png` (the flyer view looking down at the RC) to the user data folder.
- `lod_stats.gd` needs a window. It prints triangles and draw calls per quality preset.
