class_name PlayerRig
extends XROrigin3D
## The player's XR origin. Positions itself every frame for the active view:
##   FPV          - eyes at the drone camera; head look is a free 360 view.
##   THIRD_PERSON - head direction orbits the camera around the drone.
##   FLYER        - fixed pilot position on the ground; only the head moves.
## On desktop the XRCamera3D is driven by the mouse instead of an HMD.

const VM := GameEnums.ViewMode
const LOBBY := -1
const DRONE_LAYER := 1 << 1
const DESKTOP_EYE_HEIGHT := 1.65
const MOUSE_SENS := 0.0025

var camera: XRCamera3D
var left_hand: XRController3D
var right_hand: XRController3D
var controller_screen: ControllerScreen
var hud: Hud
var pilot_body: PilotBody

var drone: Drone
var pilot_transform := Transform3D.IDENTITY
var view_mode: int = LOBBY

var _ref_yaw := 0.0
var _desktop_yaw := 0.0
var _desktop_pitch := 0.0
var _orbit_distance := 2.0
var _hand_visuals: Array[Node3D] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera = XRCamera3D.new()
	camera.name = "XRCamera3D"
	camera.near = 0.03
	camera.far = 3000.0
	camera.current = true
	add_child(camera)

	left_hand = _make_hand("LeftHand", &"left_hand")
	right_hand = _make_hand("RightHand", &"right_hand")

	hud = Hud.new()
	camera.add_child(hud)

	pilot_body = PilotBody.new()
	pilot_body.name = "PilotBody"
	pilot_body.head = camera
	pilot_body.visible = false
	add_child(pilot_body)

	controller_screen = ControllerScreen.new()
	pilot_body.rc_holder.add_child(controller_screen)
	controller_screen.set_active(false)


func _make_hand(node_name: String, tracker: StringName) -> XRController3D:
	var hand := XRController3D.new()
	hand.name = node_name
	hand.tracker = tracker
	hand.pose = &"aim"
	add_child(hand)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.04, 0.03, 0.12)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.2, 0.22)
	mi.material_override = mat
	mi.position = Vector3(0, 0, 0.04)
	hand.add_child(mi)
	_hand_visuals.append(mi)
	return hand


## Reference yaw of the world-fixed views, reset to the drone's heading.
func recenter() -> void:
	if view_mode == VM.FLYER:
		_ref_yaw = FlightMath.basis_yaw(pilot_transform.basis)
	elif drone:
		_ref_yaw = FlightMath.basis_yaw(drone.global_basis)
	_desktop_yaw = 0.0
	_desktop_pitch = -0.25 if view_mode == VM.THIRD_PERSON else 0.0


func set_view_mode(mode: int) -> void:
	view_mode = mode
	recenter()
	if drone:
		_orbit_distance = drone.spec.third_person_distance
	# Hide the drone body from inside the FPV camera.
	camera.cull_mask = 0xFFFFF & ~DRONE_LAYER if mode == VM.FPV else 0xFFFFF
	var flyer := mode == VM.FLYER
	controller_screen.set_active(flyer)
	pilot_body.visible = flyer
	pilot_body.set_process(flyer)
	if flyer:
		controller_screen.drone = drone
		pilot_body.snap_to_head()
	for v in _hand_visuals:
		v.visible = Game.is_vr and not flyer
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func enter_lobby(at: Transform3D) -> void:
	drone = null
	hud.drone = null
	controller_screen.drone = null
	view_mode = LOBBY
	controller_screen.set_active(false)
	pilot_body.visible = false
	pilot_body.set_process(false)
	camera.cull_mask = 0xFFFFF
	global_transform = at
	_desktop_yaw = 0.0
	_desktop_pitch = 0.0
	for v in _hand_visuals:
		v.visible = Game.is_vr


func desktop_look(relative: Vector2) -> void:
	_desktop_yaw -= relative.x * MOUSE_SENS
	_desktop_pitch = clampf(_desktop_pitch - relative.y * MOUSE_SENS, -1.5, 1.5)


func head_forward() -> Vector3:
	return -camera.global_basis.z


func _process(delta: float) -> void:
	if not Game.is_vr:
		var eye := DESKTOP_EYE_HEIGHT if view_mode in [LOBBY, VM.FLYER] else 0.0
		camera.transform = Transform3D(Basis.from_euler(Vector3(_desktop_pitch, _desktop_yaw, 0.0)), Vector3(0, eye, 0))
	if drone == null or view_mode == LOBBY:
		return
	match view_mode:
		VM.FPV:
			_update_fpv()
		VM.THIRD_PERSON:
			_update_third_person(delta)
		VM.FLYER:
			global_transform = Transform3D(Basis(Vector3.UP, _ref_yaw), pilot_transform.origin)


func _update_fpv() -> void:
	var mount := drone.camera_transform_interpolated()
	var ref: Basis
	if Game.fpv_view_local:
		if Game.fpv_follow_attitude:
			ref = mount.basis.orthonormalized()
		else:
			ref = Basis(Vector3.UP, FlightMath.basis_yaw(mount.basis))
	else:
		ref = Basis(Vector3.UP, _ref_yaw)
	# Place the origin so the head sits exactly on the drone camera.
	global_transform = Transform3D(ref, mount.origin - ref * camera.position)


func _update_third_person(delta: float) -> void:
	var spec := drone.spec
	var drone_xf := drone.get_global_transform_interpolated()
	var target := drone_xf.origin + Vector3(0, spec.third_person_height, 0)
	var ref := Basis(Vector3.UP, FlightMath.basis_yaw(drone_xf.basis) if Game.third_view_local else _ref_yaw)
	var wanted := spec.third_person_distance
	var full_pos := FlightMath.orbit_camera_position(target, ref, camera.transform.basis, wanted)
	# Pull the camera in front of walls between it and the drone.
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(target, full_pos, 1, [drone.get_rid()])
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		wanted = maxf(target.distance_to(hit.position) - 0.2, spec.span)
	var rate := 12.0 if wanted < _orbit_distance else 3.0
	_orbit_distance = lerpf(_orbit_distance, wanted, clampf(delta * rate, 0.0, 1.0))
	var cam_pos := FlightMath.orbit_camera_position(target, ref, camera.transform.basis, _orbit_distance)
	global_transform = Transform3D(ref, cam_pos - ref * camera.position)
