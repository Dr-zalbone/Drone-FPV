"""Blender batch pipeline: transcode source GLBs in the project root into
Quest-friendly assets for Godot.

Run through tools/process_models.sh (it calls Blender in background mode):

    blender --background --factory-startup --python tools/process_models.py -- <project_root>

For every *.glb / *.gltf / *.fbx / *.obj in the project root whose file name
carries an attribution ("<title>_attribution-<author>_on_<site>.<ext>"):

* maps   -> assets/maps/<id>.glb  (decimated visual + "-colonly" collision mesh)
* drones -> assets/drones/<drone_id>.glb  (file name contains flycart / fpv / mini)
* pilot  -> assets/pilot/pilot.glb  (file name contains pilot / flyer / person / man)

It also writes assets/credits.json (consumed by the game's credits panel)
and assets/maps/manifest.json (consumed by the map loader).
"""

import json
import math
import os
import re
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

# ---------------------------------------------------------------------------
# Budgets (Quest 3S: Snapdragon XR2 Gen 2, keep frame time low).
# ---------------------------------------------------------------------------
# Maps keep their ORIGINAL geometry and textures by default; performance comes
# from spatial chunking (frustum culling) + Godot's automatic mesh LODs.
# Set "visual_tris" in MAP_OVERRIDES to force decimation for one map.
MAP_VISUAL_TRIS = None
MAP_COLLISION_TRIS = 60_000
# Chunk grid: at most CHUNK_GRID x CHUNK_GRID cells, each at least CHUNK_MIN_SIZE m
# (override per map with "chunk_size").
CHUNK_GRID = 16
CHUNK_MIN_SIZE = 48.0
# Discrete LODs per chunk: LOD0 = original, then these triangle ratios.
# The game swaps them by distance (visibility ranges), see main.gd _apply_quality.
LOD_RATIOS = (0.3, 0.08)
LOD_MIN_TRIS = 400  # smaller chunks only get LOD0
DRONE_VISUAL_TRIS = 25_000
DRONE_TEXTURE_MAX = 1024
PILOT_VISUAL_TRIS = 15_000

SOURCE_EXTS = (".glb", ".gltf", ".fbx", ".obj")

# Accepts the common misspelling "attribiution" too.
ATTRIBUTION_RE = re.compile(
    r"^(?P<title>.+?)_attrib\w*?-(?P<author>.+?)_on_(?P<site>[A-Za-z0-9]+)$",
    re.IGNORECASE,
)

DRONE_KEYWORDS = (("flycart", "flycart"), ("mini", "mini5pro"), ("fpv", "dji_fpv"))
PILOT_KEYWORDS = ("pilot", "flyer", "person", "man_", "human", "character")

# Per-map tweaks (keyed by map id).
#   scale: uniform scale baked into the exported meshes (source units -> metres)
#   spawn: optional [x, y, z] pilot position in Godot coordinates (after scale)
# Other keys are copied to the manifest as-is.
MAP_OVERRIDES = {
    # Photogrammetry chunks are authored ~100x too large.
    "eze_village_france": {"scale": 0.01},
    # Voxel model: collapse decimation shatters cubes, keep full detail
    # (33 chunks -> frustum culling + Godot auto-LOD keep it affordable).
    # Decimated LODs would shatter the cubes too, so it only gets fine chunks
    # (culling + view-distance) and no LOD1/LOD2.
    "cathedral": {"collision_collapse": False, "collision_voxel": 0.35, "lods": False, "chunk_size": 12.0},
    # Miniature city (~8 x 11 units); x250 puts the tallest towers near 500 m.
    "new_york_city_manhattan": {"scale": 250.0},
}

# Objects we never keep (we render our own sky).
DROP_OBJECT_KEYWORDS = ("skybox", "sky_sphere", "skydome")


def slugify(text):
    text = re.sub(r"[^A-Za-z0-9]+", "_", text).strip("_").lower()
    return re.sub(r"_+", "_", text)


def prettify(text):
    text = re.sub(r"[_\.]+", " ", text)
    text = re.sub(r"\s*-\s*", " - ", text)
    text = re.sub(r"\s+", " ", text).strip(" -")
    return text.title()


def parse_attribution(stem):
    m = ATTRIBUTION_RE.match(stem)
    if not m:
        return None
    return {
        "title": prettify(m.group("title")),
        "author": m.group("author").replace("_", " ").strip(),
        "site": m.group("site").capitalize(),
    }


def classify(stem):
    low = stem.lower()
    for key, drone_id in DRONE_KEYWORDS:
        if key in low:
            return "drone", drone_id
    for key in PILOT_KEYWORDS:
        if key in low:
            return "pilot", "pilot"
    return "map", None


# ---------------------------------------------------------------------------
# Blender helpers
# ---------------------------------------------------------------------------
def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_model(path):
    ext = os.path.splitext(path)[1].lower()
    if ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=path)
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path)
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=path)
    # Sketchfab exports often carry cameras and lights we do not want.
    for obj in list(bpy.context.scene.objects):
        if obj.type in {"CAMERA", "LIGHT"} or any(k in obj.name.lower() for k in DROP_OBJECT_KEYWORDS):
            bpy.data.objects.remove(obj, do_unlink=True)
    # Drop empty meshes (points / lines only).
    for obj in list(bpy.context.scene.objects):
        if obj.type == "MESH" and len(obj.data.polygons) == 0:
            bpy.data.objects.remove(obj, do_unlink=True)


def apply_root_scale(factor):
    if abs(factor - 1.0) < 1e-9:
        return
    scale = Matrix.Scale(factor, 4)
    for obj in bpy.context.scene.objects:
        if obj.parent is None:
            obj.matrix_world = scale @ obj.matrix_world
    bpy.context.view_layer.update()


def mesh_objects():
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def tri_count(obj):
    return sum(max(len(p.vertices) - 2, 0) for p in obj.data.polygons)


def apply_decimate(obj, ratio):
    """Collapse-decimate one object in place (keeps UVs/materials)."""
    if ratio >= 0.999:
        return
    if obj.data.users > 1:
        obj.data = obj.data.copy()
    mod = obj.modifiers.new("decimate", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = max(ratio, 0.01)
    mod.use_collapse_triangulate = True
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = obj.evaluated_get(depsgraph)
    new_mesh = bpy.data.meshes.new_from_object(evaluated)
    old = obj.data
    obj.modifiers.remove(mod)
    obj.data = new_mesh
    if old.users == 0:
        bpy.data.meshes.remove(old)


def apply_planar_dissolve(obj, angle_deg=1.0):
    """Lossless-ish: merge coplanar faces (great for voxel / boxy buildings)."""
    mod = obj.modifiers.new("planar", "DECIMATE")
    mod.decimate_type = "DISSOLVE"
    mod.angle_limit = math.radians(angle_deg)
    mod.use_dissolve_boundaries = False
    depsgraph = bpy.context.evaluated_depsgraph_get()
    new_mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph))
    old = obj.data
    obj.modifiers.remove(mod)
    obj.data = new_mesh
    if old.users == 0:
        bpy.data.meshes.remove(old)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()


def bake_world_transforms(objects):
    """Move every object's world transform into its mesh data."""
    for obj in objects:
        mw = obj.matrix_world.copy()
        if obj.data.users > 1:
            obj.data = obj.data.copy()
        obj.parent = None
        obj.data.transform(mw)
        obj.matrix_world = Matrix.Identity(4)
    # Empties (old parents) are no longer needed.
    for obj in list(bpy.context.scene.objects):
        if obj.type == "EMPTY":
            bpy.data.objects.remove(obj, do_unlink=True)


def chunk_visuals(objects, asset_id, cell_size=None, make_lods=True):
    """Split the map into a horizontal grid of chunks (faces binned by centre).
    Geometry, UVs, normals and materials are copied untouched, so quality is
    identical to the source; chunks enable culling and per-chunk LOD."""
    bake_world_transforms(objects)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    if len(objects) > 1:
        bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    mesh = joined.data
    xs = [v.co.x for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    min_x, min_y = min(xs), min(ys)
    extent = max(max(xs) - min_x, max(ys) - min_y, 0.001)
    cell = cell_size or max(extent / CHUNK_GRID, CHUNK_MIN_SIZE)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.faces.ensure_lookup_table()
    cells = {}
    for face in bm.faces:
        c = face.calc_center_median()
        key = (int((c.x - min_x) // cell), int((c.y - min_y) // cell))
        cells.setdefault(key, set()).add(face.index)
    chunks = []
    for key, keep in sorted(cells.items()):
        part = bm.copy()
        part.faces.ensure_lookup_table()
        drop = [f for f in part.faces if f.index not in keep]
        bmesh.ops.delete(part, geom=drop, context="FACES")
        name = f"{asset_id}_chunk_{key[0]}_{key[1]}_lod0"
        chunk_mesh = bpy.data.meshes.new(name)
        part.to_mesh(chunk_mesh)
        part.free()
        for mat in mesh.materials:
            chunk_mesh.materials.append(mat)
        # Origin at the chunk centre so distance-based LOD / visibility
        # ranges in Godot are measured per chunk, not from the map origin.
        verts = chunk_mesh.vertices
        lo = Vector((min(v.co.x for v in verts), min(v.co.y for v in verts), min(v.co.z for v in verts)))
        hi = Vector((max(v.co.x for v in verts), max(v.co.y for v in verts), max(v.co.z for v in verts)))
        centre = (lo + hi) * 0.5
        chunk_mesh.transform(Matrix.Translation(-centre))
        obj = bpy.data.objects.new(name, chunk_mesh)
        obj.location = centre
        bpy.context.scene.collection.objects.link(obj)
        chunks.append(obj)
    bm.free()
    bpy.data.objects.remove(joined, do_unlink=True)
    lod_count = 0
    if make_lods:
        for obj in chunks:
            if tri_count(obj) < LOD_MIN_TRIS:
                continue
            for level, ratio in enumerate(LOD_RATIOS, start=1):
                lod = obj.copy()
                lod.data = obj.data.copy()
                lod.name = obj.name[:-1] + str(level)
                lod.data.name = lod.name
                bpy.context.scene.collection.objects.link(lod)
                apply_decimate(lod, ratio)
                lod_count += 1
    print(f"   chunks: {len(chunks)} ({cell:.0f} m cells), LOD meshes: {lod_count}")
    return chunks, cell


def decimate_to_budget(objects, budget):
    total = sum(tri_count(o) for o in objects)
    if budget is None or total <= budget or total == 0:
        return total, total
    ratio = budget / total
    for obj in objects:
        apply_decimate(obj, ratio)
    return total, sum(tri_count(o) for o in objects)


def build_collision(objects, name, budget, collapse=True, voxel=0.0):
    """Merge all meshes (world space) into one material-less collision mesh."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    bm = bmesh.new()
    for obj in objects:
        evaluated = obj.evaluated_get(depsgraph)
        tmp = evaluated.to_mesh()
        tmp_bm = bmesh.new()
        tmp_bm.from_mesh(tmp)
        tmp_bm.transform(obj.matrix_world)
        tmp_mesh = bpy.data.meshes.new("_tmp")
        tmp_bm.to_mesh(tmp_mesh)
        tmp_bm.free()
        evaluated.to_mesh_clear()
        bm.from_mesh(tmp_mesh)
        bpy.data.meshes.remove(tmp_mesh)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.01)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.clear()
    # UV seams / colour attributes block edge collapses; collision needs none.
    while mesh.uv_layers:
        mesh.uv_layers.remove(mesh.uv_layers[0])
    while mesh.color_attributes:
        mesh.color_attributes.remove(mesh.color_attributes[0])
    col = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(col)
    before = tri_count(col)
    if voxel > 0.0:
        # Rebuild as a clean voxel surface (ideal for blocky / voxel art).
        mod = col.modifiers.new("remesh", "REMESH")
        mod.mode = "BLOCKS"
        mod.octree_depth = max(1, math.ceil(math.log2(max(col.dimensions) / voxel)))
        mod.use_remove_disconnected = False
        depsgraph = bpy.context.evaluated_depsgraph_get()
        remeshed = bpy.data.meshes.new_from_object(col.evaluated_get(depsgraph))
        col.modifiers.remove(mod)
        old = col.data
        col.data = remeshed
        bpy.data.meshes.remove(old)
        print(f"   voxel remesh ({voxel} m): {before} -> {tri_count(col)}")
    if tri_count(col) > budget:
        apply_planar_dissolve(col)
        print(f"   planar dissolve: {before} -> {tri_count(col)}")
    for _ in range(4 if collapse else 0):
        current = tri_count(col)
        if current <= budget * 1.05:
            break
        apply_decimate(col, budget / current)
    return col, before, tri_count(col)


def downscale_textures(max_size):
    for img in bpy.data.images:
        if img.size[0] == 0 or img.size[1] == 0:
            continue
        w, h = img.size
        biggest = max(w, h)
        if biggest <= max_size:
            continue
        factor = max_size / biggest
        img.scale(max(1, int(w * factor)), max(1, int(h * factor)))


def world_bounds(objects):
    lo = [math.inf] * 3
    hi = [-math.inf] * 3
    for obj in objects:
        for corner in obj.bound_box:
            world = obj.matrix_world @ Vector(corner)
            for i in range(3):
                lo[i] = min(lo[i], world[i])
                hi[i] = max(hi[i], world[i])
    # Blender is Z-up; glTF/Godot are Y-up (x, z, -y).
    return {
        "min": [lo[0], lo[2], -hi[1]],
        "max": [hi[0], hi[2], -lo[1]],
    }


def export_glb(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        export_apply=True,
        export_image_format="AUTO",
        export_draco_mesh_compression_enable=False,  # Godot cannot read Draco
        export_jpeg_quality=100,  # only used if an image must be re-encoded
        export_animations=False,
        export_cameras=False,
        export_lights=False,
    )


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def process(root, only=None):
    assets = os.path.join(root, "assets")
    credits = []
    maps = []
    sources = sorted(
        f for f in os.listdir(root)
        if f.lower().endswith(SOURCE_EXTS) and os.path.isfile(os.path.join(root, f))
    )
    previous = {}
    credits_path = os.path.join(assets, "credits.json")
    manifest_path = os.path.join(assets, "maps", "manifest.json")
    if only:
        # Partial run: keep entries of models we are not reprocessing.
        for path, key in ((credits_path, "credits"), (manifest_path, "maps")):
            if os.path.exists(path):
                with open(path, encoding="utf-8") as fh:
                    previous[key] = json.load(fh)
        sources = [f for f in sources if only.lower() in f.lower()]
        done = set(sources)
        credits = [c for c in previous.get("credits", []) if c.get("source_file") not in done]
        keep_ids = {c["id"] for c in credits if c.get("kind") == "map"}
        maps = [m for m in previous.get("maps", []) if m.get("id") in keep_ids]
    for filename in sources:
        stem = os.path.splitext(filename)[0]
        attribution = parse_attribution(stem)
        if attribution is None:
            print(f"[skip] {filename}: no attribution in file name")
            continue
        kind, asset_id = classify(stem)
        if kind == "map":
            asset_id = slugify(attribution["title"])
        print(f"[{kind}] {filename} -> {asset_id}")

        reset_scene()
        import_model(os.path.join(root, filename))
        objects = mesh_objects()

        if kind == "map":
            overrides = MAP_OVERRIDES.get(asset_id, {})
            apply_root_scale(float(overrides.get("scale", 1.0)))
            before, after = decimate_to_budget(objects, overrides.get("visual_tris", MAP_VISUAL_TRIS))
            objects, cell = chunk_visuals(
                objects, asset_id, overrides.get("chunk_size"), bool(overrides.get("lods", True)))
            col, cb, ca = build_collision(
                objects, f"{asset_id}_collision-colonly", MAP_COLLISION_TRIS,
                collapse=bool(overrides.get("collision_collapse", True)),
                voxel=float(overrides.get("collision_voxel", 0.0)))
            bounds = world_bounds(objects)
            out = os.path.join(assets, "maps", f"{asset_id}.glb")
            export_glb(out)
            print(f"   visual tris {before} -> {after}, collision tris {cb} -> {ca}")
            entry = {
                "id": asset_id,
                "title": attribution["title"],
                "scene": f"res://assets/maps/{asset_id}.glb",
                "bounds": bounds,
                "visual_tris": after,
                "collision_tris": ca,
                "chunks": len(objects),
                "chunk_size": cell,
                "lods": bool(overrides.get("lods", True)),
            }
            entry.update({k: v for k, v in overrides.items()
                          if k not in ("scale", "visual_tris", "collision_collapse", "collision_voxel",
                                       "lods", "chunk_size")})
            maps.append(entry)
        else:
            budget = DRONE_VISUAL_TRIS if kind == "drone" else PILOT_VISUAL_TRIS
            before, after = decimate_to_budget(objects, budget)
            downscale_textures(DRONE_TEXTURE_MAX)
            sub = "drones" if kind == "drone" else "pilot"
            out = os.path.join(assets, sub, f"{asset_id}.glb")
            export_glb(out)
            print(f"   visual tris {before} -> {after}")

        credits.append({
            "kind": kind,
            "id": asset_id,
            "title": attribution["title"],
            "author": attribution["author"],
            "site": attribution["site"],
            "source_file": filename,
        })

    os.makedirs(os.path.join(assets, "maps"), exist_ok=True)
    order = {f: i for i, f in enumerate(sorted(os.listdir(root)))}
    credits.sort(key=lambda c: order.get(c.get("source_file"), 0))
    maps.sort(key=lambda m: m["id"])
    with open(credits_path, "w", encoding="utf-8") as fh:
        json.dump(credits, fh, indent=2)
    with open(manifest_path, "w", encoding="utf-8") as fh:
        json.dump(maps, fh, indent=2)
    print(f"done: {len(maps)} maps, {len(credits)} credited models")


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    # Optional 2nd argument: only reprocess source files containing this text.
    process(os.path.abspath(args[0] if args else os.getcwd()), args[1] if len(args) > 1 else None)
