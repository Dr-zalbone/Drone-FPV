# Drone FPV VR (Godot 4.7, Meta Quest 3S)

VR drone simulator. You can fly a DJI Mini 5 Pro, a DJI FPV or a DJI FlyCart 30 in
imported Sketchfab worlds. Every view gives a full 360° look-around.

## Views

| View | Who can use it | Head movement |
|---|---|---|
| **FPV (goggles)** | all drones | Free 360° look from the drone camera. It never steers the drone. The default view **turns with the drone**. |
| **3rd person** | all drones | Turning your head **orbits** the camera around the drone. The default view is **world-fixed**. |
| **Flyer (pilot)** | Mini 5 Pro, FlyCart | You stand still as the pilot and can only move your head. The RC in your left hand shows the live drone camera. |

Press **X** (or **L**) to switch the active view between "turns with drone" and "world-fixed".
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

## Adding models

Put the model files in the project root. The file name must carry the attribution:

```
<title>_attribution-<author>_on_<site>.glb      (.gltf / .fbx / .obj also work)
```

- File names containing `flycart`, `mini` or `fpv` are drones. They replace the built-in placeholder for that drone.
- File names containing `pilot`, `flyer`, `person` or `human` are the pilot figure.
- Every other file is a world (map).

Then run the pipeline. It needs Blender (flatpak `org.blender.Blender` or `blender` on the PATH):

```bash
tools/process_models.sh
```

The pipeline does the following:
- Decimates the map visuals to 350k triangles and downsizes textures to 2048 px.
- Builds a merged collision mesh of up to 60k triangles. The mesh name ends in `-colonly`, so Godot imports it as a trimesh `StaticBody3D`.
- Writes `assets/maps/*.glb`, `assets/drones/*.glb`, `assets/pilot/pilot.glb`, `assets/maps/manifest.json` and `assets/credits.json`.

The credits panel on the start screen reads `credits.json`.
The raw source files stay in the root. Their `.import` is set to `skip`, so Godot does not import them or ship them in the APK.

To reprocess only one model, pass part of its file name: `tools/process_models.sh cathedral`.

Per-map tuning lives in `MAP_OVERRIDES` in `tools/process_models.py`:

| Map | Override | Why |
|---|---|---|
| Eze Village | `scale 0.01`, skybox mesh dropped | The photogrammetry is authored about 100× too large. The game draws its own sky. |
| New York City Manhattan | `scale 250` | The source is an 8 × 11 m miniature. |
| Cathedral | no visual decimation, collision voxel-remeshed at 0.35 m | It is voxel art: edge-collapse decimation shatters the cubes. |

Other override keys: `spawn: [x, y, z]` (pilot position), `visual_tris`, `collision_collapse`, `collision_voxel`.

Current per-map budgets (visual / collision triangles):
- Cathedral: 1.01M / 393k
- Eze Village: 300k / 60k
- New York City Manhattan: 337k / 225k

The cathedral is the heaviest on Quest, so check its frame rate on the headset first.

## Quest 3S export

1. Install the Godot 4.7.2 Android export templates (Editor → Manage Export Templates).
2. Install the Android SDK and set its path in Editor Settings → Export → Android. Your current setting points to `~/Android/Sdk`.
3. Optional: install the *Godot OpenXR Vendors* plugin from the Asset Library for Meta-specific features.
4. Project → Export → **Quest 3S** (OpenXR mode, arm64, ETC2/ASTC textures).

Performance settings: the Mobile renderer, 2× MSAA, dynamic foveation, no realtime shadows, auto mesh LODs, and a 90 Hz refresh/physics rate with physics interpolation.
The RC screen viewport renders only in Flyer view.

## Tests

```bash
flatpak run --filesystem=$PWD org.godotengine.Godot --headless --path . --script res://tests/run_tests.gd
```

```bash
flatpak run --filesystem=$PWD org.godotengine.Godot --headless --path . --script res://tests/smoke_main.gd
```

- `run_tests.gd` holds the unit tests (flight math, attribution parsing, drone catalog, view rules) and a physics integration test.
- `smoke_main.gd` loads every map with every drone, cycles all views, pauses, resets and returns to the menu.
- `screenshot_maps.gd` needs a window (no `--headless`). It saves `shot_<map>_<view>.png` screenshots to the user data folder.
