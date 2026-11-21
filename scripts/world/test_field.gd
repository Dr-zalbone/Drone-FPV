class_name TestField
extends RefCounted
## Built-in "Valley Town" map, generated in code (no imported assets):
## rolling hills with mountains at the rim, a river valley, a town on a flat
## plateau (downtown towers, houses with pitched roofs, streets), forest,
## racing gates and a lookout hill where the pilot starts.
##
## Quest budget: the terrain is split into 8x8 chunks (frustum culling), and
## every building / tree / road shares a handful of merged meshes or one
## MultiMesh, so the whole map is roughly 30 draw calls.

const WORLD_MASK := 1
const SEED := 1337

const SIZE := 1404.0          # metres, square, centred on the origin (multiple of CELL)
const CELL := 6.0             # terrain grid spacing (m)
const CHUNKS := 8             # terrain chunks per side
const WATER_LEVEL := -3.0

const TOWN_CENTER := Vector2(-120.0, 40.0)
const TOWN_RADIUS := 200.0    # flat plateau radius (m)
const TOWN_HEIGHT := 8.0
const BLOCK := 44.0           # street grid pitch (m)
const ROAD_WIDTH := 10.0

const LOOKOUT := Vector2(70.0, 330.0)
const LOOKOUT_HEIGHT := 46.0
const LOOKOUT_PAD := 14.0     # flat top radius (m)

const STOREY := 3.4
const BAY := 3.2

static var _noise: FastNoiseLite
static var _detail: FastNoiseLite


# --------------------------------------------------------------------------
# Terrain shape (pure functions, unit-tested)
# --------------------------------------------------------------------------
static func _noises() -> void:
	if _noise:
		return
	_noise = FastNoiseLite.new()
	_noise.seed = SEED
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.0022
	_noise.fractal_octaves = 5
	_detail = FastNoiseLite.new()
	_detail.seed = SEED + 1
	_detail.frequency = 0.004
	_detail.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_detail.fractal_octaves = 4


## X position of the river's centre line at a given Z.
static func river_x(z: float) -> float:
	return 230.0 + 70.0 * sin(z / 210.0) + 28.0 * sin(z / 77.0 + 1.0)


static func height_at(x: float, z: float) -> float:
	_noises()
	var p := Vector2(x, z)
	var h := _noise.get_noise_2d(x, z) * 32.0 + 12.0
	# Mountains rise towards the rim of the map.
	var rim := smoothstep(380.0, 660.0, p.length())
	h += rim * (70.0 + (_detail.get_noise_2d(x, z) * 0.5 + 0.5) * 90.0)
	# Flat town plateau.
	h = lerpf(TOWN_HEIGHT, h, smoothstep(TOWN_RADIUS, TOWN_RADIUS + 90.0, p.distance_to(TOWN_CENTER)))
	# Lookout hill with a flat top.
	var to_lookout := p.distance_to(LOOKOUT)
	var hill := LOOKOUT_HEIGHT * (1.0 - smoothstep(LOOKOUT_PAD, 130.0, to_lookout))
	h = lerpf(LOOKOUT_HEIGHT, maxf(h, hill), smoothstep(LOOKOUT_PAD, LOOKOUT_PAD + 10.0, to_lookout))
	# River channel, carved last.
	var bank := smoothstep(12.0, 60.0, absf(x - river_x(z)))
	return lerpf(WATER_LEVEL - 4.0, h, bank)


static func normal_at(x: float, z: float, e := 1.0) -> Vector3:
	var dx := height_at(x + e, z) - height_at(x - e, z)
	var dz := height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()


static func in_town(x: float, z: float, margin := 0.0) -> bool:
	return Vector2(x, z).distance_to(TOWN_CENTER) < TOWN_RADIUS - margin


## Pilot transform on the lookout, facing the town.
static func spawn_transform() -> Transform3D:
	var to_town := (TOWN_CENTER - LOOKOUT).normalized()
	var yaw := atan2(-to_town.x, -to_town.y)
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(LOOKOUT.x, LOOKOUT_HEIGHT, LOOKOUT.y))


# --------------------------------------------------------------------------
# Build
# --------------------------------------------------------------------------
static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "ValleyTown"
	var n := int(SIZE / CELL)
	var heights := _height_grid(n)
	root.add_child(_terrain_collision(heights, n))
	_add_terrain_chunks(root, heights, n)
	root.add_child(_water())
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	_add_town(root, rng)
	_add_forest(root, rng)
	_add_lookout(root)
	_add_gates(root)
	root.set_meta(&"spawn", spawn_transform())
	return root


static func _height_grid(n: int) -> PackedFloat32Array:
	var data := PackedFloat32Array()
	data.resize((n + 1) * (n + 1))
	var half := SIZE * 0.5
	for iz in n + 1:
		for ix in n + 1:
			data[iz * (n + 1) + ix] = height_at(ix * CELL - half, iz * CELL - half)
	return data


static func _terrain_collision(heights: PackedFloat32Array, n: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Terrain"
	body.collision_layer = WORLD_MASK
	var shape := HeightMapShape3D.new()
	shape.map_width = n + 1
	shape.map_depth = n + 1
	# Uniform scale (safest for every physics backend): heights in cell units.
	var scaled := heights.duplicate()
	for i in scaled.size():
		scaled[i] /= CELL
	shape.map_data = scaled
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3.ONE * CELL
	body.add_child(cs)
	return body


static func _terrain_color(h: float, nrm: Vector3, x: float, z: float) -> Color:
	var v := _detail.get_noise_2d(x * 3.0, z * 3.0) * 0.5 + 0.5
	var grass := Color(0.27, 0.45, 0.2).lerp(Color(0.42, 0.52, 0.25), v)
	var rock := Color(0.46, 0.44, 0.4).lerp(Color(0.36, 0.34, 0.32), v)
	var c := grass.lerp(rock, smoothstep(0.86, 0.7, nrm.y))
	c = c.lerp(Color(0.72, 0.68, 0.55), smoothstep(WATER_LEVEL + 2.5, WATER_LEVEL + 0.5, h))
	c = c.lerp(Color(0.92, 0.93, 0.95), smoothstep(115.0, 140.0, h) * smoothstep(0.6, 0.8, nrm.y))
	return c


static func _add_terrain_chunks(root: Node3D, heights: PackedFloat32Array, n: int) -> void:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _noise_texture(0.08, 0.75, 1.0)
	mat.roughness = 1.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var half := SIZE * 0.5
	var per := n / CHUNKS
	for cz in CHUNKS:
		for cx in CHUNKS:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var x0 := cx * per
			var z0 := cz * per
			var x1 := n if cx == CHUNKS - 1 else x0 + per
			var z1 := n if cz == CHUNKS - 1 else z0 + per
			var w := x1 - x0 + 1
			for iz in range(z0, z1 + 1):
				for ix in range(x0, x1 + 1):
					var x := ix * CELL - half
					var z := iz * CELL - half
					var h := heights[iz * (n + 1) + ix]
					var hl := heights[iz * (n + 1) + maxi(ix - 1, 0)]
					var hr := heights[iz * (n + 1) + mini(ix + 1, n)]
					var hd := heights[maxi(iz - 1, 0) * (n + 1) + ix]
					var hu := heights[mini(iz + 1, n) * (n + 1) + ix]
					var nrm := Vector3(hl - hr, 2.0 * CELL, hd - hu).normalized()
					st.set_normal(nrm)
					st.set_color(_terrain_color(h, nrm, x, z))
					st.set_uv(Vector2(x, z) / 8.0)
					st.add_vertex(Vector3(x, h, z))
			for iz in z1 - z0:
				for ix in x1 - x0:
					var a := iz * w + ix
					st.add_index(a)
					st.add_index(a + 1)
					st.add_index(a + w)
					st.add_index(a + 1)
					st.add_index(a + w + 1)
					st.add_index(a + w)
			var mi := MeshInstance3D.new()
			mi.name = "terrain_%d_%d" % [cx, cz]
			mi.mesh = st.commit()
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)


static func _water() -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * SIZE
	var mi := MeshInstance3D.new()
	mi.name = "River"
	mi.mesh = plane
	mi.position.y = WATER_LEVEL
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/sea.gdshader")
	mat.set_shader_parameter(&"water_color", Color(0.12, 0.27, 0.3))
	mat.set_shader_parameter(&"wave_normal", _noise_texture(0.02, 0.0, 1.0, true))
	mi.material_override = mat
	return mi


static func _noise_texture(freq: float, lo: float, hi: float, normal := false) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = SEED + 7
	noise.frequency = freq
	noise.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.generate_mipmaps = true
	tex.noise = noise
	if normal:
		tex.as_normal_map = true
		tex.bump_strength = 4.0
	else:
		var ramp := Gradient.new()
		ramp.set_color(0, Color(lo, lo, lo))
		ramp.set_color(1, Color(hi, hi, hi))
		tex.color_ramp = ramp
	return tex


# --------------------------------------------------------------------------
# Town
# --------------------------------------------------------------------------
## Facade texture: one bay x one storey, a window in a wall (tinted by the
## material colour). Mapped in world space, so windows line up on any box.
static func _facade_texture() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	img.fill(Color(0.92, 0.92, 0.92))
	for y in range(16, 50):
		for x in range(14, 50):
			var glass := 0.2 + 0.12 * float(y - 16) / 34.0
			img.set_pixel(x, y, Color(glass, glass + 0.04, glass + 0.09))
	for x in range(10, 54):  # sill
		img.set_pixel(x, 51, Color(0.75, 0.75, 0.75))
		img.set_pixel(x, 52, Color(0.75, 0.75, 0.75))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _wall_material(tex: Texture2D, color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = color
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3(1.0 / BAY, 1.0 / STOREY, 1.0 / BAY)
	mat.roughness = 0.85
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat


static func _flat_material(color: Color, roughness := 0.9) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat


## Callers list corners so (b - a) x (c - a) points outward. Godot's front
## faces are clockwise as seen by the viewer, so emit them as a, c, b.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.set_normal((b - a).cross(c - a).normalized())
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(b)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(st, a, b, c)
	_tri(st, a, c, d)


## Axis-aligned box from y0 to y1 (no bottom face).
static func _box(st: SurfaceTool, cx: float, cz: float, sx: float, sz: float, y0: float, y1: float) -> void:
	var x0 := cx - sx * 0.5
	var x1 := cx + sx * 0.5
	var z0 := cz - sz * 0.5
	var z1 := cz + sz * 0.5
	_quad(st, Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1))  # +Z
	_quad(st, Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x1, y1, z0))  # -Z
	_quad(st, Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1))  # +X
	_quad(st, Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0))  # -X
	_quad(st, Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3(x0, y1, z0))  # top


## Gable roof over a box; the ridge runs along X when along_x.
static func _gable(st: SurfaceTool, cx: float, cz: float, sx: float, sz: float, y0: float, rise: float, along_x: bool) -> void:
	var o := 0.4  # eaves overhang
	var x0 := cx - sx * 0.5 - o
	var x1 := cx + sx * 0.5 + o
	var z0 := cz - sz * 0.5 - o
	var z1 := cz + sz * 0.5 + o
	var top := y0 + rise
	if along_x:
		var r0 := Vector3(x0, top, cz)
		var r1 := Vector3(x1, top, cz)
		_quad(st, Vector3(x0, y0, z1), Vector3(x1, y0, z1), r1, r0)
		_quad(st, Vector3(x1, y0, z0), Vector3(x0, y0, z0), r0, r1)
		_tri(st, Vector3(x0, y0, z0), Vector3(x0, y0, z1), r0)
		_tri(st, Vector3(x1, y0, z1), Vector3(x1, y0, z0), r1)
	else:
		var r0 := Vector3(cx, top, z0)
		var r1 := Vector3(cx, top, z1)
		_quad(st, Vector3(x1, y0, z1), Vector3(x1, y0, z0), r0, r1)
		_quad(st, Vector3(x0, y0, z0), Vector3(x0, y0, z1), r1, r0)
		_tri(st, Vector3(x1, y0, z0), Vector3(x0, y0, z0), r0)
		_tri(st, Vector3(x0, y0, z1), Vector3(x1, y0, z1), r1)


static func _add_town(root: Node3D, rng: RandomNumberGenerator) -> void:
	var facade := _facade_texture()
	var wall_colors := [Color(0.93, 0.88, 0.78), Color(0.78, 0.8, 0.83), Color(0.8, 0.52, 0.42), Color(0.98, 0.97, 0.94)]
	var walls: Array[SurfaceTool] = []
	for _c in wall_colors:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		walls.append(st)
	var flat_roofs := SurfaceTool.new()
	flat_roofs.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tile_roofs := SurfaceTool.new()
	tile_roofs.begin(Mesh.PRIMITIVE_TRIANGLES)
	var roads := SurfaceTool.new()
	roads.begin(Mesh.PRIMITIVE_TRIANGLES)

	var body := StaticBody3D.new()
	body.name = "Buildings"
	body.collision_layer = WORLD_MASK
	var ground := TOWN_HEIGHT
	var cells := int(TOWN_RADIUS * 2.0 / BLOCK)
	var origin := TOWN_CENTER - Vector2.ONE * TOWN_RADIUS
	# Streets: one strip per grid line, clipped to the plateau.
	for i in cells + 1:
		var t := origin.x + i * BLOCK
		var span := sqrt(maxf(TOWN_RADIUS * TOWN_RADIUS - pow(t - TOWN_CENTER.x, 2.0), 0.0)) - 15.0
		if span > 0.0:
			_quad(roads, Vector3(t - ROAD_WIDTH * 0.5, ground + 0.05, TOWN_CENTER.y + span),
				Vector3(t + ROAD_WIDTH * 0.5, ground + 0.05, TOWN_CENTER.y + span),
				Vector3(t + ROAD_WIDTH * 0.5, ground + 0.05, TOWN_CENTER.y - span),
				Vector3(t - ROAD_WIDTH * 0.5, ground + 0.05, TOWN_CENTER.y - span))
		var tz := origin.y + i * BLOCK
		span = sqrt(maxf(TOWN_RADIUS * TOWN_RADIUS - pow(tz - TOWN_CENTER.y, 2.0), 0.0)) - 15.0
		if span > 0.0:
			_quad(roads, Vector3(TOWN_CENTER.x - span, ground + 0.09, tz - ROAD_WIDTH * 0.5),
				Vector3(TOWN_CENTER.x - span, ground + 0.09, tz + ROAD_WIDTH * 0.5),
				Vector3(TOWN_CENTER.x + span, ground + 0.09, tz + ROAD_WIDTH * 0.5),
				Vector3(TOWN_CENTER.x + span, ground + 0.09, tz - ROAD_WIDTH * 0.5))

	# Buildings: 2x2 lots per block; tall downtown, houses towards the edge.
	var lot := (BLOCK - ROAD_WIDTH) * 0.5
	for bz in cells:
		for bx in cells:
			for lz in 2:
				for lx in 2:
					var cx := origin.x + bx * BLOCK + ROAD_WIDTH * 0.5 + lot * (lx + 0.5)
					var cz := origin.y + bz * BLOCK + ROAD_WIDTH * 0.5 + lot * (lz + 0.5)
					var d := Vector2(cx, cz).distance_to(TOWN_CENTER) / TOWN_RADIUS
					if d > 0.88 or rng.randf() < 0.12:
						continue  # edge of town / a small park
					var sx := lot * rng.randf_range(0.6, 0.9)
					var sz := lot * rng.randf_range(0.6, 0.9)
					var wall := walls[rng.randi() % walls.size()]
					var y0 := ground - 0.5
					var shape := BoxShape3D.new()
					var height: float
					if d < 0.45:
						# Downtown: towers rounded to whole storeys, flat roof slab.
						height = STOREY * roundf(lerpf(18.0, 4.0, d / 0.45) * rng.randf_range(0.6, 1.4))
						_box(wall, cx, cz, sx, sz, y0, ground + height)
						_box(flat_roofs, cx, cz, sx + 0.6, sz + 0.6, ground + height, ground + height + 0.6)
						height += 0.6
					else:
						height = STOREY * float(rng.randi_range(1, 3))
						_box(wall, cx, cz, sx, sz, y0, ground + height)
						var along_x := sx >= sz
						var rise := (sz if along_x else sx) * 0.35
						_gable(tile_roofs, cx, cz, sx, sz, ground + height, rise, along_x)
						height += rise * 0.6
					shape.size = Vector3(sx, height + 0.5, sz)
					var cs := CollisionShape3D.new()
					cs.shape = shape
					cs.position = Vector3(cx, y0 + shape.size.y * 0.5, cz)
					body.add_child(cs)

	root.add_child(body)
	for i in walls.size():
		_add_mesh(root, "walls_%d" % i, walls[i], _wall_material(facade, wall_colors[i]))
	_add_mesh(root, "roofs_flat", flat_roofs, _flat_material(Color(0.32, 0.33, 0.35)))
	_add_mesh(root, "roofs_tiled", tile_roofs, _flat_material(Color(0.62, 0.3, 0.22)))
	_add_mesh(root, "roads", roads, _flat_material(Color(0.2, 0.2, 0.22), 0.95))


static func _add_mesh(root: Node3D, mesh_name: String, st: SurfaceTool, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = mesh_name
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


# --------------------------------------------------------------------------
# Forest
# --------------------------------------------------------------------------
## One low-poly conifer (trunk + two cones), 1 m base height, vertex coloured.
static func _tree_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 6
	var parts := [
		[0.0, 0.25, 0.06, 0.06, Color(0.36, 0.25, 0.16)],
		[0.18, 0.7, 0.32, 0.0, Color(0.16, 0.34, 0.17)],
		[0.45, 1.0, 0.24, 0.0, Color(0.2, 0.4, 0.2)],
	]
	for part: Array in parts:
		var y0: float = part[0]
		var y1: float = part[1]
		var r0: float = part[2]
		var r1: float = part[3]
		st.set_color(part[4])
		for i in sides:
			var a0 := TAU * i / sides
			var a1 := TAU * (i + 1) / sides
			var b0 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var b1 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var t0 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var t1 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			if r1 > 0.0:
				_quad(st, b0, t0, t1, b1)
			else:
				_tri(st, b0, t0, b1)
			_tri(st, b1, Vector3(0, y0, 0), b0)  # underside
	return st.commit()


static func _add_forest(root: Node3D, rng: RandomNumberGenerator) -> void:
	var xforms: Array[Transform3D] = []
	var body := StaticBody3D.new()
	body.name = "Trees"
	body.collision_layer = WORLD_MASK
	var half := SIZE * 0.5 - 20.0
	var tries := 0
	while xforms.size() < 1600 and tries < 20000:
		tries += 1
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		if in_town(x, z, -25.0) or absf(x - river_x(z)) < 30.0:
			continue
		if Vector2(x, z).distance_to(LOOKOUT) < LOOKOUT_PAD + 12.0:
			continue
		var h := height_at(x, z)
		if h > 105.0 or h < WATER_LEVEL + 1.5 or normal_at(x, z).y < 0.82:
			continue
		# Clumps: forest density follows a noise field.
		if _detail.get_noise_2d(x * 0.5, z * 0.5) < -0.1 and rng.randf() < 0.8:
			continue
		var s := rng.randf_range(7.0, 14.0)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(x, h - 0.3, z))
		xforms.append(xf)
		var shape := CylinderShape3D.new()
		shape.radius = s * 0.22
		shape.height = s
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = Vector3(x, h + s * 0.5, z)
		body.add_child(cs)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _tree_mesh()
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Forest"
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)
	root.add_child(body)


# --------------------------------------------------------------------------
# Lookout and gates
# --------------------------------------------------------------------------
static func _add_lookout(root: Node3D) -> void:
	var pad := CylinderMesh.new()
	pad.top_radius = 6.0
	pad.bottom_radius = 6.4
	pad.height = 0.4
	pad.radial_segments = 24
	var mi := MeshInstance3D.new()
	mi.name = "LookoutPad"
	mi.mesh = pad
	mi.material_override = _flat_material(Color(0.55, 0.55, 0.52))
	mi.position = Vector3(LOOKOUT.x, LOOKOUT_HEIGHT - 0.15, LOOKOUT.y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## Racing gates on a loop around the town, 4 m above the ground. All gate
## parts are drawn by one MultiMesh (unit cube scaled per part).
static func _add_gates(root: Node3D) -> void:
	var gate_mat := StandardMaterial3D.new()
	gate_mat.albedo_color = Color(1.0, 0.45, 0.1)
	gate_mat.emission_enabled = true
	gate_mat.emission = Color(1.0, 0.4, 0.05)
	gate_mat.emission_energy_multiplier = 0.6
	var parts := [[Vector3(0.4, 6.0, 0.4), Vector3(-3.0, 0, 0)], [Vector3(0.4, 6.0, 0.4), Vector3(3.0, 0, 0)],
			[Vector3(6.4, 0.4, 0.4), Vector3(0, 3.0, 0)], [Vector3(6.4, 0.4, 0.4), Vector3(0, -3.0, 0)]]
	var count := 10
	var radius := TOWN_RADIUS + 40.0
	var body := StaticBody3D.new()
	body.name = "Gates"
	body.collision_layer = WORLD_MASK
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BoxMesh.new()
	mm.instance_count = count * parts.size()
	for i in count:
		var a := i * TAU / count
		var x := TOWN_CENTER.x + sin(a) * radius
		var z := TOWN_CENTER.y - cos(a) * radius
		var gate_xf := Transform3D(Basis(Vector3.UP, -a), Vector3(x, maxf(height_at(x, z), WATER_LEVEL) + 4.0, z))
		for j in parts.size():
			var size: Vector3 = parts[j][0]
			var part_xf := gate_xf * Transform3D(Basis.IDENTITY, parts[j][1])
			mm.set_instance_transform(i * parts.size() + j, part_xf * Transform3D(Basis.from_scale(size), Vector3.ZERO))
			var box := BoxShape3D.new()
			box.size = size
			var cs := CollisionShape3D.new()
			cs.shape = box
			cs.transform = part_xf
			body.add_child(cs)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "GateMeshes"
	mmi.multimesh = mm
	mmi.material_override = gate_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)
	root.add_child(body)
