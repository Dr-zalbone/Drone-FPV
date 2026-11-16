class_name UIPointer
extends Node3D
## Laser pointer for 3D panels: right controller in VR, mouse on desktop.

const MAX_DISTANCE := 12.0

var rig: PlayerRig
var enabled := true

var _laser: MeshInstance3D
var _dot: MeshInstance3D
var _panel: Panel3D
var _hit := Vector3.ZERO
var _pressed_panel: Panel3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.3, 0.8, 1.0)
	mat.no_depth_test = true
	mat.render_priority = 20
	var beam := BoxMesh.new()
	beam.size = Vector3(0.004, 0.004, 1.0)
	_laser = MeshInstance3D.new()
	_laser.mesh = beam
	_laser.material_override = mat
	_laser.top_level = true
	add_child(_laser)
	var dot := SphereMesh.new()
	dot.radius = 0.012
	dot.height = 0.024
	_dot = MeshInstance3D.new()
	_dot.mesh = dot
	_dot.material_override = mat
	_dot.top_level = true
	add_child(_dot)


func _ray() -> Array[Vector3]:
	if Game.is_vr:
		var hand := rig.right_hand
		return [hand.global_position, -hand.global_basis.z]
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		return []
	var mouse := get_viewport().get_mouse_position()
	return [rig.camera.project_ray_origin(mouse), rig.camera.project_ray_normal(mouse)]


func _process(_delta: float) -> void:
	_panel = null
	_laser.visible = false
	_dot.visible = false
	if not enabled or rig == null:
		return
	var ray := _ray()
	if ray.is_empty():
		return
	var from := ray[0]
	var to := from + ray[1] * MAX_DISTANCE
	var query := PhysicsRayQueryParameters3D.create(from, to, Panel3D.UI_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var panel := (hit.collider as Node).get_parent() as Panel3D
	if panel == null or not panel.is_visible_in_tree():
		return
	_panel = panel
	_hit = hit.position
	panel.pointer_move(_hit, _pressed_panel == panel)
	_dot.visible = true
	_dot.global_position = _hit
	if Game.is_vr:
		var length := from.distance_to(_hit)
		_laser.visible = true
		var up := Vector3.UP if absf(ray[1].y) < 0.99 else Vector3.FORWARD
		_laser.global_transform = Transform3D(Basis.looking_at(ray[1], up), from + ray[1] * length * 0.5)
		_laser.scale = Vector3(1, 1, length)


func click(pressed: bool) -> void:
	if pressed:
		_pressed_panel = _panel
		if _panel:
			_panel.pointer_button(_hit, true)
	elif _pressed_panel and is_instance_valid(_pressed_panel):
		# Release goes to the panel that got the press, even if the ray left it.
		_pressed_panel.pointer_button(_hit, false)
		_pressed_panel = null


func scroll(up: bool) -> void:
	if _panel:
		_panel.pointer_scroll(_hit, up)
