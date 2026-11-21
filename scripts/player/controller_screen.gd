class_name ControllerScreen
extends Node3D
## Handheld remote controller with a live screen showing the drone's camera.
## Used in Flyer view. The SubViewport only renders while active.

const SCREEN_PX := Vector2i(960, 540)
const DRONE_LAYER := 1 << 1
## The RC itself. The drone camera must never see it: the screen samples the
## drone camera's own render target, so seeing it is a feedback loop
## ("same texture in framebuffer attachment and a uniform").
const RC_LAYER := 1 << 2

var drone: Drone

var _viewport: SubViewport
var _cam: Camera3D
var _left_stick: Node3D
var _right_stick: Node3D
var _telemetry: Label3D
var _tick := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_viewport = SubViewport.new()
	_viewport.size = SCREEN_PX
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.positional_shadow_atlas_size = 0
	add_child(_viewport)
	_cam = Camera3D.new()
	_cam.fov = 80.0
	_cam.far = 1500.0
	_cam.cull_mask = 0xFFFFF & ~DRONE_LAYER & ~RC_LAYER
	_viewport.add_child(_cam)

	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.12, 0.13)
	var body := BoxMesh.new()
	body.size = Vector3(0.42, 0.04, 0.16)
	add_child(_mesh(body, dark, Vector3(0, 0, 0.03)))
	# Grips on both sides.
	var grip := CapsuleMesh.new()
	grip.radius = 0.03
	grip.height = 0.14
	for side in [-1.0, 1.0]:
		var g := _mesh(grip, dark, Vector3(side * 0.2, -0.02, 0.06))
		g.rotation.x = deg_to_rad(90)
		add_child(g)
	# Screen bezel and screen (tilted toward the face like a DJI RC).
	var bezel := BoxMesh.new()
	bezel.size = Vector3(0.35, 0.205, 0.012)
	# Screen lies on top of the RC, tipped a little further toward the face.
	var bezel_node := _mesh(bezel, dark, Vector3(0, 0.03, -0.01))
	bezel_node.rotation.x = deg_to_rad(-85)
	add_child(bezel_node)
	var screen := QuadMesh.new()
	screen.size = Vector2(0.33, 0.186)
	var screen_mat := StandardMaterial3D.new()
	screen_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen_mat.albedo_texture = _viewport.get_texture()
	var screen_node := _mesh(screen, screen_mat, Vector3(0, 0, 0.0065))
	bezel_node.add_child(screen_node)
	# Telemetry strip under the screen (the head-locked HUD hides in Flyer view).
	_telemetry = Label3D.new()
	_telemetry.font_size = 32
	_telemetry.pixel_size = 0.0005
	_telemetry.outline_size = 6
	_telemetry.position = Vector3(0, -0.087, 0.007)
	_telemetry.shaded = false
	_telemetry.layers = RC_LAYER
	bezel_node.add_child(_telemetry)

	var stick_mesh := CylinderMesh.new()
	stick_mesh.top_radius = 0.008
	stick_mesh.bottom_radius = 0.008
	stick_mesh.height = 0.03
	_left_stick = _mesh(stick_mesh, dark, Vector3(-0.15, 0.03, 0.04))
	_right_stick = _mesh(stick_mesh, dark, Vector3(0.15, 0.03, 0.04))
	add_child(_left_stick)
	add_child(_right_stick)


func _mesh(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = RC_LAYER
	return mi


func attach_to(parent: Node3D) -> void:
	if get_parent() != parent:
		if get_parent():
			get_parent().remove_child(self)
		parent.add_child(self)
	transform = Transform3D.IDENTITY


func set_active(active: bool) -> void:
	visible = active
	if _viewport:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	set_process(active)


func _process(delta: float) -> void:
	if drone == null or not is_instance_valid(drone):
		return
	_cam.global_transform = drone.camera_transform_interpolated()
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.1
		var v := drone.linear_velocity
		var dist := drone.global_position.distance_to(global_position)
		_telemetry.text = "%s   %4.1f m/s   H %+5.1f m   D %5.1f m%s" % [
			GameEnums.FLIGHT_NAMES[drone.flight_mode], v.length(),
			drone.global_position.y - global_position.y + 1.2, dist,
			"   CRASHED" if drone.is_crashed else ""]
	var i := drone.input
	_left_stick.rotation = Vector3(-i.y * 0.4, 0, -i.x * 0.4)
	_right_stick.rotation = Vector3(-i.w * 0.4, 0, -i.z * 0.4)
