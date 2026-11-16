class_name DroneVisual
extends RefCounted
## Builds a drone's visual: the imported model when assets/drones/<id>.glb
## exists, otherwise a lightweight procedural placeholder.

const PROP_META := "is_prop"


static func build(spec: DroneSpec) -> Node3D:
	var root: Node3D
	if spec.model_path != "":
		root = _load_model(spec)
	if root == null:
		root = _placeholder(spec)
	root.name = "Visual"
	_set_layer(root, 1 << 1)
	return root


static func find_props(root: Node) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for node in root.find_children("*", "Node3D", true, false):
		if node.has_meta(PROP_META) or String(node.name).to_lower().begins_with("prop"):
			out.append(node)
	return out


static func _load_model(spec: DroneSpec) -> Node3D:
	var packed := load(spec.model_path) as PackedScene
	if packed == null:
		return null
	var model := packed.instantiate() as Node3D
	var holder := Node3D.new()
	holder.add_child(model)
	# Auto-scale so the model's largest horizontal extent matches the real span.
	var aabb := _combined_aabb(model)
	var extent := maxf(aabb.size.x, aabb.size.z)
	if extent > 0.0001:
		var s := spec.span / extent
		model.scale = Vector3.ONE * s
		model.position = -aabb.get_center() * s
	return holder


static func _combined_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for node in root.find_children("*", "VisualInstance3D", true, false):
		var vi := node as VisualInstance3D
		var xf := _relative_transform(root, vi)
		var box := xf * vi.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


static func _relative_transform(root: Node3D, node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


static func _set_layer(root: Node, layer: int) -> void:
	for node in root.find_children("*", "VisualInstance3D", true, false):
		(node as VisualInstance3D).layers = layer
	if root is VisualInstance3D:
		(root as VisualInstance3D).layers = layer


static func _mat(color: Color, emissive := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.6
	if emissive:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 2.0
	return m


static func _mesh(mesh: Mesh, mat: Material, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _placeholder(spec: DroneSpec) -> Node3D:
	var root := Node3D.new()
	var body_mat := _mat(spec.body_color)
	var dark := _mat(Color(0.08, 0.08, 0.09))
	var prop_mat := _mat(Color(0.15, 0.15, 0.16, 0.6))
	prop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var body := BoxMesh.new()
	body.size = spec.body_size * Vector3(0.7, 0.8, 0.9)
	root.add_child(_mesh(body, body_mat))

	# Camera / gimbal at the front.
	var cam := SphereMesh.new()
	cam.radius = spec.body_size.y * 0.3
	cam.height = cam.radius * 2.0
	root.add_child(_mesh(cam, dark, spec.camera_offset))

	# Front LEDs (green) / rear (red) help orientation in 3rd person.
	var led := SphereMesh.new()
	led.radius = maxf(spec.span * 0.02, 0.006)
	led.height = led.radius * 2.0

	var arm_count := 4
	var radius := spec.span * 0.5
	var prop_r := spec.span * (0.22 if spec.rotor_count == 4 else 0.18)
	for i in arm_count:
		var angle := PI / 4.0 + i * TAU / arm_count
		var dir := Vector3(sin(angle), 0, -cos(angle))
		var arm := BoxMesh.new()
		arm.size = Vector3(spec.span * 0.05, spec.body_size.y * 0.25, radius)
		var arm_node := _mesh(arm, body_mat, dir * radius * 0.5)
		arm_node.rotation.y = -angle
		root.add_child(arm_node)

		var motor := CylinderMesh.new()
		motor.top_radius = spec.span * 0.035
		motor.bottom_radius = motor.top_radius
		motor.height = spec.body_size.y * 0.5
		var motor_pos := dir * radius + Vector3(0, spec.body_size.y * 0.15, 0)
		root.add_child(_mesh(motor, dark, motor_pos))

		var front := dir.z < 0.0
		root.add_child(_mesh(led, _mat(Color(0.1, 1, 0.2) if front else Color(1, 0.1, 0.1), true),
				dir * radius - Vector3(0, spec.body_size.y * 0.15, 0)))

		# Coaxial rotors for 8-rotor craft (FlyCart).
		var layers := 2 if spec.rotor_count == 8 else 1
		for l in layers:
			var prop := Node3D.new()
			prop.name = "Prop%d_%d" % [i, l]
			prop.set_meta(PROP_META, true)
			prop.set_meta("cw", (i + l) % 2 == 0)
			var y := spec.body_size.y * (0.45 if l == 0 else -0.25)
			prop.position = dir * radius + Vector3(0, y, 0)
			var blade := BoxMesh.new()
			blade.size = Vector3(prop_r * 2.0, 0.004 if spec.span < 1.0 else 0.02, prop_r * 0.18)
			prop.add_child(_mesh(blade, prop_mat))
			root.add_child(prop)

	if spec.id == &"flycart":
		# Cargo box and landing gear.
		var cargo := BoxMesh.new()
		cargo.size = Vector3(0.6, 0.25, 0.6)
		root.add_child(_mesh(cargo, _mat(Color(0.9, 0.55, 0.1)), Vector3(0, -spec.body_size.y * 0.25, 0)))
		for side in [-1.0, 1.0]:
			var skid := BoxMesh.new()
			skid.size = Vector3(0.05, 0.05, spec.body_size.z * 1.1)
			root.add_child(_mesh(skid, dark, Vector3(side * spec.body_size.x * 0.45, -spec.body_size.y * 0.5, 0)))
	return root
