class_name Drone
extends RigidBody3D
## Physics drone with DJI-style angle modes (Cine/Normal/Sport) and an
## acro "Manual" mode. Built entirely from a DroneSpec.

signal crashed
signal reset_done

const FM := GameEnums.FlightMode

var spec: DroneSpec
var flight_mode: int = FM.NORMAL
var input := Vector4.ZERO  # x = yaw, y = throttle, z = roll, w = pitch (all -1..1)
var is_crashed := false
var armed := true
## FPV "look steers yaw" (DJI head-tracking style): world yaw the drone turns
## to face, set by PlayerRig from the camera. NAN = normal yaw-stick control.
## The rig folds the yaw stick into this heading, so the stick is ignored here.
var look_yaw := NAN

var camera_mount: Node3D
var visual: Node3D

var _spawn := Transform3D.IDENTITY
var _target_yaw := 0.0
var _prev_velocity := Vector3.ZERO
var _manual_rates := Vector3.ZERO
var _props: Array[Node3D] = []
var _prop_speed := 0.0
var _kill_y := -500.0


func setup(drone_spec: DroneSpec, spawn: Transform3D, kill_y: float) -> void:
	spec = drone_spec
	_spawn = spawn
	_kill_y = kill_y
	name = "Drone"
	mass = spec.mass
	gravity_scale = 1.0
	continuous_cd = true
	can_sleep = false
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.5
	contact_monitor = true
	max_contacts_reported = 4
	collision_layer = 1 << 1
	collision_mask = 1
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	var mat := PhysicsMaterial.new()
	mat.friction = 0.6
	mat.bounce = 0.15
	physics_material_override = mat

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = spec.body_size
	shape.shape = box
	add_child(shape)

	visual = DroneVisual.build(spec)
	add_child(visual)
	_props = DroneVisual.find_props(visual)

	camera_mount = Node3D.new()
	camera_mount.name = "CameraMount"
	camera_mount.position = spec.camera_offset
	camera_mount.rotation.x = deg_to_rad(spec.camera_tilt_deg)
	add_child(camera_mount)

	set_flight_mode(spec.default_mode())
	global_transform = spawn
	_target_yaw = FlightMath.basis_yaw(spawn.basis)


func set_flight_mode(mode: int) -> void:
	if not spec.has_mode(mode):
		mode = spec.default_mode()
	flight_mode = mode
	_target_yaw = FlightMath.basis_yaw(global_basis)
	_manual_rates = Vector3.ZERO


func reset_to_spawn() -> void:
	is_crashed = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_prev_velocity = Vector3.ZERO
	global_transform = _spawn
	_target_yaw = FlightMath.basis_yaw(_spawn.basis)
	reset_physics_interpolation()
	reset_done.emit()


func speed() -> float:
	return linear_velocity.length()


func camera_transform_interpolated() -> Transform3D:
	return get_global_transform_interpolated() * camera_mount.transform


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if spec == null:
		return
	var dt := state.step
	var v := state.linear_velocity

	# Crash detection: a sudden velocity change while touching something.
	if not is_crashed and state.get_contact_count() > 0:
		if (_prev_velocity - v).length() > spec.crash_speed:
			is_crashed = true
			crashed.emit()
	_prev_velocity = v

	if is_crashed or not armed:
		return

	if flight_mode == FM.MANUAL:
		_integrate_manual(state, dt)
	else:
		_integrate_angle(state, dt)


func _integrate_angle(state: PhysicsDirectBodyState3D, dt: float) -> void:
	var p := spec.mode_params(flight_mode)
	if is_nan(look_yaw):
		_target_yaw = wrapf(_target_yaw - input.x * deg_to_rad(p.yaw_rate_deg) * dt, -PI, PI)
	else:
		_target_yaw = look_yaw
	var desired := FlightMath.desired_velocity(_target_yaw, input.z, input.w, input.y, p)
	var accel := FlightMath.velocity_accel(state.linear_velocity, desired, p)
	# Cancel gravity and apply the commanded acceleration.
	state.apply_central_force(mass * (accel - state.total_gravity))
	var target := FlightMath.target_attitude(_target_yaw, accel, p.max_tilt_deg)
	state.angular_velocity = FlightMath.attitude_correction(state.transform.basis, target, p.attitude_gain)


func _integrate_manual(state: PhysicsDirectBodyState3D, dt: float) -> void:
	var r := spec.manual_rates_deg
	# Local body rates: pitch fwd -> nose down (-X), yaw right -> -Y, roll right -> -Z.
	var wanted := Vector3(-input.w * deg_to_rad(r.x), -input.x * deg_to_rad(r.y), -input.z * deg_to_rad(r.z))
	_manual_rates = _manual_rates.lerp(wanted, clampf(dt * 25.0, 0.0, 1.0))
	var body_basis := state.transform.basis
	state.angular_velocity = body_basis * _manual_rates
	var throttle := FlightMath.manual_throttle(input.y, spec.manual_thrust_to_weight)
	var thrust := body_basis.y * mass * FlightMath.GRAVITY * spec.manual_thrust_to_weight * throttle
	var k := FlightMath.drag_coefficient(mass, spec.manual_thrust_to_weight, spec.manual_max_speed)
	var v := state.linear_velocity
	state.apply_central_force(thrust - v * v.length() * k)


func _physics_process(delta: float) -> void:
	if global_position.y < _kill_y:
		reset_to_spawn()
	# Prop spin (visual only).
	var target_spin := 0.0
	if not is_crashed and armed:
		target_spin = 60.0 + 40.0 * maxf(input.y, 0.0)
	_prop_speed = lerpf(_prop_speed, target_spin, clampf(delta * 3.0, 0.0, 1.0))
	for prop in _props:
		prop.rotate_object_local(Vector3.UP, _prop_speed * delta * (1.0 if prop.get_meta("cw", true) else -1.0))
