class_name MapDressing
extends RefCounted
## Per-map extras driven by manifest flags (MAP_OVERRIDES in tools/process_models.py):
##   "unshaded": true      photogrammetry already has its lighting baked into
##                         the photos; skip real-time lighting (cheaper, and
##                         it is not lit twice).
##   "surround": "sea"     water / ground plane that fills the empty void
##   "surround": "ground"  around the scanned area out to the horizon.

const WORLD_MASK := 1
const SEA_COLOR := Color(0.13, 0.3, 0.38)
const GROUND_COLOR := Color(0.36, 0.42, 0.3)


## Returns the number of materials switched to unshaded.
static func make_unshaded(map: Node) -> int:
	var cache := {}  # source material -> unshaded copy (keeps sharing intact)
	for node in map.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i) as BaseMaterial3D
			if src == null:
				continue
			if not cache.has(src):
				var mat := src.duplicate() as BaseMaterial3D
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				cache[src] = mat
			mi.set_surface_override_material(i, cache[src])
	return cache.size()


## Height for the surround plane: just below the lowest ground found along the
## map's border, so it never pokes through the scanned surface.
static func surround_level(space: PhysicsDirectSpaceState3D, bounds: AABB) -> float:
	var top := bounds.end.y + 10.0
	var bottom := bounds.position.y - 10.0
	var lowest := INF
	var samples := 24
	for i in samples:
		var t := float(i) / samples
		for p: Vector2 in [Vector2(t, 0.03), Vector2(t, 0.97), Vector2(0.03, t), Vector2(0.97, t)]:
			var x := bounds.position.x + bounds.size.x * p.x
			var z := bounds.position.z + bounds.size.z * p.y
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, top, z), Vector3(x, bottom, z), WORLD_MASK)
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				lowest = minf(lowest, (hit.position as Vector3).y)
	if lowest == INF:
		return bounds.position.y
	return lowest - 0.6


static func make_surround(kind: String, level: float, center: Vector3, radius: float) -> Node3D:
	var body := StaticBody3D.new()
	body.name = "Surround"
	body.collision_layer = WORLD_MASK
	body.position = Vector3(center.x, level, center.z)
	# Infinite plane: one cheap shape, and the drone can always land/crash on it.
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	body.add_child(shape)
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * radius * 2.0
	var mi := MeshInstance3D.new()
	mi.name = "SurroundMesh"
	mi.mesh = plane
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = _sea_material() if kind == "sea" else _ground_material()
	body.add_child(mi)
	return body


static func _detail_noise(frequency: float, as_normal: bool) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.frequency = frequency
	noise.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.as_normal_map = as_normal
	tex.bump_strength = 4.0
	tex.generate_mipmaps = true
	tex.noise = noise
	return tex


static func _sea_material() -> Material:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/sea.gdshader")
	mat.set_shader_parameter(&"water_color", SEA_COLOR)
	mat.set_shader_parameter(&"wave_normal", _detail_noise(0.02, true))
	return mat


static func _ground_material() -> Material:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = GROUND_COLOR
	mat.albedo_texture = _detail_noise(0.03, false)
	mat.uv1_scale = Vector3(400, 400, 1)
	mat.roughness = 1.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat
