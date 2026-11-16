class_name Panel3D
extends Node3D
## Renders a Control tree into a SubViewport shown on a quad in the world.
## UIPointer feeds it laser / mouse hits converted to 2D mouse events.

const UI_LAYER := 1 << 19

var content: Control
var size_m := Vector2(1.6, 1.0)
var resolution := Vector2i(1280, 800)

var _viewport: SubViewport
var _last_px := Vector2.ZERO


func _init(control: Control, meters := Vector2(1.6, 1.0), px := Vector2i(1280, 800)) -> void:
	content = control
	size_m = meters
	resolution = px


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_viewport = SubViewport.new()
	_viewport.size = resolution
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.gui_embed_subwindows = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_viewport)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewport.add_child(content)

	var quad := QuadMesh.new()
	quad.size = size_m
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = _viewport.get_texture()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat.render_priority = 5
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

	var body := StaticBody3D.new()
	body.collision_layer = UI_LAYER
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size_m.x, size_m.y, 0.01)
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()


func _on_visibility_changed() -> void:
	# Keep the hidden panel's collider out of the pointer ray.
	for child in get_children():
		if child is StaticBody3D:
			(child as StaticBody3D).collision_layer = UI_LAYER if is_visible_in_tree() else 0


func world_to_px(hit: Vector3) -> Vector2:
	var l := to_local(hit)
	return Vector2((l.x / size_m.x + 0.5) * resolution.x, (0.5 - l.y / size_m.y) * resolution.y)


func pointer_move(hit: Vector3, button_held := false) -> void:
	var px := world_to_px(hit)
	var ev := InputEventMouseMotion.new()
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if button_held else 0
	ev.position = px
	ev.global_position = px
	ev.relative = px - _last_px
	_last_px = px
	_viewport.push_input(ev)


func pointer_button(hit: Vector3, pressed: bool) -> void:
	var px := world_to_px(hit)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	ev.position = px
	ev.global_position = px
	_viewport.push_input(ev)


func pointer_scroll(hit: Vector3, up: bool) -> void:
	var px := world_to_px(hit)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
		ev.pressed = pressed
		ev.position = px
		ev.global_position = px
		_viewport.push_input(ev)


## Place the panel `distance` metres in front of a camera, facing it, level.
func face_camera(cam: Node3D, distance := 1.6, drop := 0.15) -> void:
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var pos := cam.global_position + fwd * distance - Vector3(0, drop, 0)
	# Quad front is +Z, so -Z must point away from the camera.
	global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), pos)
