class_name PilotBody
extends Node3D
## First-person pilot body for Flyer view. Lives in the XR origin's space,
## stands under the head and turns ONLY on yaw with the head, so the RC held
## at chest height is always found by looking down, whichever way you face.

## Below the eyes / in front of the chest where the RC is held (metres).
const RC_DROP := 0.5
const RC_REACH := 0.36
const RC_TILT_DEG := 40.0
## How fast the body catches up with head yaw (1/s). High = nearly locked.
const YAW_FOLLOW := 10.0

var head: Node3D
var rc_holder: Node3D

var _yaw := 0.0
var _torso: MeshInstance3D
var _arms: Array[MeshInstance3D] = []


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.2, 0.3, 0.45)
	var torso_mesh := CapsuleMesh.new()
	torso_mesh.radius = 0.17
	torso_mesh.height = 0.7
	_torso = MeshInstance3D.new()
	_torso.mesh = torso_mesh
	_torso.material_override = cloth
	_torso.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_torso)

	rc_holder = Node3D.new()
	rc_holder.name = "RCHolder"
	add_child(rc_holder)

	var arm_mesh := CapsuleMesh.new()
	arm_mesh.radius = 0.045
	arm_mesh.height = 0.42
	for side in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		arm.mesh = arm_mesh
		arm.material_override = cloth
		arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		arm.set_meta("side", side)
		add_child(arm)
		_arms.append(arm)


func snap_to_head() -> void:
	_yaw = FlightMath.basis_yaw(head.transform.basis)
	_update(0.0, true)


func _process(delta: float) -> void:
	if head:
		_update(delta, false)


func _update(delta: float, snap: bool) -> void:
	var head_xf := head.transform  # head pose inside the XR origin
	var target_yaw := FlightMath.basis_yaw(head_xf.basis)
	_yaw = target_yaw if snap else lerp_angle(_yaw, target_yaw, clampf(delta * YAW_FOLLOW, 0.0, 1.0))
	var eye_y := maxf(head_xf.origin.y, 0.9)
	# Stand under the head; yaw only, never pitch / roll.
	transform = Transform3D(Basis(Vector3.UP, _yaw), Vector3(head_xf.origin.x, 0.0, head_xf.origin.z))
	_torso.position = Vector3(0, eye_y - 0.78, 0.1)
	rc_holder.transform = Transform3D(
			Basis.from_euler(Vector3(deg_to_rad(RC_TILT_DEG), 0, 0)),
			Vector3(0, eye_y - RC_DROP, -RC_REACH))
	# Arms from the shoulders to the RC grips.
	for arm in _arms:
		var side: float = arm.get_meta("side")
		var shoulder := Vector3(side * 0.2, eye_y - 0.3, 0.05)
		var hand := rc_holder.position + Vector3(side * 0.2, -0.02, 0.06)
		var dir := hand - shoulder
		arm.position = shoulder + dir * 0.5
		arm.basis = Basis(Quaternion(Vector3.UP, dir.normalized()))
		(arm.mesh as CapsuleMesh).height = dir.length()
