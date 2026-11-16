class_name WorldBuilder
extends RefCounted
## Environment, lobby, built-in test field, spawn finding and the pilot figure.

const WORLD_MASK := 1


static func make_environment() -> Array[Node]:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.52, 0.85)
	sky_mat.sky_horizon_color = Color(0.72, 0.8, 0.9)
	sky_mat.ground_horizon_color = Color(0.6, 0.62, 0.65)
	sky_mat.ground_bottom_color = Color(0.25, 0.25, 0.27)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = false
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.1
	# Shadows are expensive on Quest; drones read fine without them.
	sun.shadow_enabled = false
	return [we, sun]


static func _ground(size: float, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = WORLD_MASK
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size, 1.0, size)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.uv1_scale = Vector3(size / 4.0, size / 4.0, 1)
	mat.albedo_texture = _checker_texture()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	body.add_child(mi)
	return body


static func _checker_texture() -> ImageTexture:
	var img := Image.create(64, 64, true, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var c := 0.95 if ((x / 32) + (y / 32)) % 2 == 0 else 0.8
			img.set_pixel(x, y, Color(c, c, c))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func make_lobby() -> Node3D:
	var root := Node3D.new()
	root.name = "Lobby"
	root.add_child(_ground(40.0, Color(0.45, 0.5, 0.55)))
	return root


## Flat field with obstacles and gates for testing without imported maps.
static func make_test_field() -> Node3D:
	var root := Node3D.new()
	root.name = "TestField"
	root.add_child(_ground(600.0, Color(0.42, 0.55, 0.38)))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.72, 0.68)
	for i in 40:
		var size := Vector3(rng.randf_range(4, 14), rng.randf_range(4, 40), rng.randf_range(4, 14))
		var pos := Vector3(rng.randf_range(-200, 200), size.y * 0.5, rng.randf_range(-200, 200))
		if pos.length() < 25.0:
			continue
		root.add_child(_box(size, pos, mat))
	# Racing gates in a loop.
	var gate_mat := StandardMaterial3D.new()
	gate_mat.albedo_color = Color(1.0, 0.45, 0.1)
	gate_mat.emission_enabled = true
	gate_mat.emission = Color(1.0, 0.4, 0.05)
	gate_mat.emission_energy_multiplier = 0.6
	for i in 8:
		var a := i * TAU / 8.0
		var center := Vector3(sin(a) * 60.0, 3.0, -cos(a) * 60.0 - 90.0)
		var gate := Node3D.new()
		gate.position = center
		gate.rotation.y = -a
		for part: Array in [[Vector3(0.3, 4.0, 0.3), Vector3(-2.0, 0, 0)], [Vector3(0.3, 4.0, 0.3), Vector3(2.0, 0, 0)],
				[Vector3(4.3, 0.3, 0.3), Vector3(0, 2.0, 0)], [Vector3(4.3, 0.3, 0.3), Vector3(0, -2.0, 0)]]:
			gate.add_child(_box(part[0], part[1], gate_mat))
		root.add_child(gate)
	return root


static func _box(size: Vector3, pos: Vector3, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = WORLD_MASK
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)
	return body


static func visual_bounds(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var box := mi.global_transform * mi.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


## Picks a pilot standing spot: the lowest walkable surface with open sky
## above it near the middle of the map (streets / plazas rather than rooftops
## or overhangs), facing the most open horizontal direction.
static func find_pilot_spawn(space: PhysicsDirectSpaceState3D, bounds: AABB) -> Transform3D:
	var center := bounds.get_center()
	var top := bounds.end.y + 20.0
	var bottom := bounds.position.y - 20.0
	var best := Vector3(center.x, bounds.position.y, center.z)
	var best_score := INF
	var steps := 11
	for ix in steps:
		for iz in steps:
			var fx := lerpf(0.2, 0.8, ix / float(steps - 1))
			var fz := lerpf(0.2, 0.8, iz / float(steps - 1))
			var x := bounds.position.x + bounds.size.x * fx
			var z := bounds.position.z + bounds.size.z * fz
			var hit := ground_at(space, Vector3(x, top, z), bottom)
			if hit.is_empty() or (hit.normal as Vector3).y < 0.85:
				continue
			var p: Vector3 = hit.position
			# Reject spots under roofs / overhangs (single-sided meshes can let
			# the downward ray slip through from above).
			if not _ray(space, p + Vector3(0, 0.3, 0), p + Vector3(0, 300, 0)).is_empty():
				continue
			var score: float = p.y + Vector2(x - center.x, z - center.z).length() * 0.02
			if score < best_score:
				best_score = score
				best = p
	return Transform3D(Basis(Vector3.UP, open_yaw(space, best + Vector3(0, 1.6, 0))), best)


## Yaw (around +Y, 0 = -Z) of the horizontal direction with the most free space.
static func open_yaw(space: PhysicsDirectSpaceState3D, eye: Vector3, reach := 60.0) -> float:
	var best_yaw := 0.0
	var best_free := -1.0
	for i in 16:
		var yaw := i * TAU / 16.0
		var dir := Basis(Vector3.UP, yaw) * Vector3.FORWARD
		var hit := _ray(space, eye, eye + dir * reach)
		var free := reach if hit.is_empty() else eye.distance_to(hit.position)
		if free > best_free + 0.01:
			best_free = free
			best_yaw = yaw
	return best_yaw


static func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK)
	query.hit_back_faces = true
	return space.intersect_ray(query)


static func ground_at(space: PhysicsDirectSpaceState3D, from: Vector3, bottom_y: float) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, Vector3(from.x, bottom_y, from.z), WORLD_MASK)
	return space.intersect_ray(query)


## The pilot figure (imported assets/pilot/pilot.glb or a placeholder).
static func make_pilot() -> Node3D:
	var root := Node3D.new()
	root.name = "Pilot"
	var path := "res://assets/pilot/pilot.glb"
	if ResourceLoader.exists(path):
		var model := (load(path) as PackedScene).instantiate() as Node3D
		root.add_child(model)
		var aabb := DroneVisual._combined_aabb(model)
		if aabb.size.y > 0.01:
			model.scale = Vector3.ONE * (1.75 / aabb.size.y)
			model.position.y = -aabb.position.y * model.scale.y
		return root
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.85, 0.7, 0.58)
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.2, 0.3, 0.45)
	var body := CapsuleMesh.new()
	body.radius = 0.2
	body.height = 1.45
	var body_mi := MeshInstance3D.new()
	body_mi.mesh = body
	body_mi.material_override = cloth
	body_mi.position.y = 0.725
	root.add_child(body_mi)
	var head := SphereMesh.new()
	head.radius = 0.12
	head.height = 0.24
	var head_mi := MeshInstance3D.new()
	head_mi.mesh = head
	head_mi.material_override = skin
	head_mi.position.y = 1.6
	root.add_child(head_mi)
	return root
