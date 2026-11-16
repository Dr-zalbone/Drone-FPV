class_name FlightMath
extends RefCounted
## Pure flight / camera math. Kept free of scene state so it is unit-testable.

const GRAVITY := 9.8


## Deadzone + exponential curve on a stick axis in [-1, 1].
static func shape_axis(value: float, deadzone := 0.08, expo := 0.3) -> float:
	var mag := absf(value)
	if mag <= deadzone:
		return 0.0
	mag = clampf((mag - deadzone) / (1.0 - deadzone), 0.0, 1.0)
	mag = mag * (1.0 - expo) + mag * mag * mag * expo
	return signf(value) * mag


## Desired world velocity for angle modes.
## sticks: x = roll (right +), y = pitch (forward +); throttle in [-1, 1].
static func desired_velocity(yaw: float, roll: float, pitch: float, throttle: float, p: Dictionary) -> Vector3:
	var horizontal := Vector2(roll, pitch)
	if horizontal.length() > 1.0:
		horizontal = horizontal.normalized()
	var local := Vector3(horizontal.x, 0.0, -horizontal.y) * float(p.max_speed)
	var vertical := throttle * (float(p.max_climb) if throttle > 0.0 else float(p.max_descent))
	var world := Basis(Vector3.UP, yaw) * local
	world.y = vertical
	return world


## Acceleration that moves current velocity toward desired, capped per axis group.
static func velocity_accel(current: Vector3, desired: Vector3, p: Dictionary) -> Vector3:
	var response := maxf(float(p.response), 0.01)
	var accel := (desired - current) / response
	var horiz := Vector2(accel.x, accel.z).limit_length(float(p.accel))
	var vert := clampf(accel.y, -float(p.accel) * 1.5, float(p.accel) * 1.5)
	return Vector3(horiz.x, vert, horiz.y)


## Body attitude a multirotor would need for a given world acceleration.
static func target_attitude(yaw: float, accel: Vector3, max_tilt_deg: float) -> Basis:
	var yaw_basis := Basis(Vector3.UP, yaw)
	var local := yaw_basis.inverse() * accel
	var max_tilt := deg_to_rad(max_tilt_deg)
	# Forward accel (-Z) pitches the nose down (negative X rotation).
	var pitch := clampf(atan2(local.z, GRAVITY), -max_tilt, max_tilt)
	# Rightward accel (+X) rolls right side down (negative Z rotation).
	var roll := clampf(-atan2(local.x, GRAVITY), -max_tilt, max_tilt)
	return yaw_basis * Basis.from_euler(Vector3(pitch, 0.0, roll))


## Angular velocity (world) that rotates `current` toward `target` at `gain` 1/s.
static func attitude_correction(current: Basis, target: Basis, gain: float) -> Vector3:
	var q_err := Quaternion(target.orthonormalized()) * Quaternion(current.orthonormalized()).inverse()
	if q_err.w < 0.0:
		q_err = -q_err
	var angle := q_err.get_angle()
	if angle < 0.0001:
		return Vector3.ZERO
	return q_err.get_axis() * angle * gain


## Yaw angle (radians, around +Y) of a basis' forward (-Z) axis.
static func basis_yaw(b: Basis) -> float:
	var fwd := -b.z
	return atan2(-fwd.x, -fwd.z)


## Manual (acro) throttle: centred stick = hover so spring-loaded VR sticks work.
static func manual_throttle(stick: float, thrust_to_weight: float) -> float:
	var hover := 1.0 / maxf(thrust_to_weight, 1.0)
	if stick >= 0.0:
		return lerpf(hover, 1.0, stick)
	return lerpf(hover, 0.0, -stick)


## Quadratic drag coefficient giving terminal velocity `max_speed` at full thrust.
static func drag_coefficient(mass: float, thrust_to_weight: float, max_speed: float) -> float:
	return mass * GRAVITY * thrust_to_weight / (max_speed * max_speed)


## 3rd-person orbit: camera world position for a head orientation in a reference frame.
static func orbit_camera_position(target: Vector3, ref_basis: Basis, head_basis: Basis, distance: float) -> Vector3:
	var forward := -(ref_basis * head_basis).z
	return target - forward * distance
