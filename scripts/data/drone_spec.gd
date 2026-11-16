class_name DroneSpec
extends RefCounted
## Flight characteristics of one drone model.
##
## Angle-mode values (CINE / NORMAL / SPORT) live in [member angle_modes];
## MANUAL (acro) values in the manual_* fields.

var id: StringName
var display_name: String
## Physical mass in kg. Used for collisions; flight feel comes from the limits below.
var mass: float
## Collision box size in metres (x = width, y = height, z = length).
var body_size: Vector3
## Motor-to-motor diagonal (m). Drives the placeholder model and model auto-scaling.
var span: float
var rotor_count := 4
var body_color := Color(0.25, 0.25, 0.27)
## Gimbal / FPV camera position relative to the drone origin.
var camera_offset := Vector3(0, 0, -0.1)
## Fixed camera uptilt in degrees (FPV drones fly with the camera tilted up).
var camera_tilt_deg := 0.0
var third_person_distance := 2.0
var third_person_height := 0.4
## Pilot can stand and fly line-of-sight with the RC screen (Flyer view).
var allows_flyer := true
var flight_modes: Array[int] = []
## FlightMode -> { max_speed, max_climb, max_descent, yaw_rate_deg, max_tilt_deg, accel, response, attitude_gain }
var angle_modes: Dictionary = {}
var manual_rates_deg := Vector3(500, 400, 500)  # pitch, yaw, roll
var manual_thrust_to_weight := 4.0
var manual_max_speed := 39.0
## Relative speed (m/s) above which an impact counts as a crash.
var crash_speed := 6.0
## res:// path of an imported model; empty -> procedural placeholder.
var model_path := ""


func mode_params(mode: int) -> Dictionary:
	if angle_modes.has(mode):
		return angle_modes[mode]
	return angle_modes.values()[0]


func has_mode(mode: int) -> bool:
	return mode in flight_modes


func next_mode(current: int) -> int:
	var idx := flight_modes.find(current)
	return flight_modes[(idx + 1) % flight_modes.size()]


func default_mode() -> int:
	return GameEnums.FlightMode.NORMAL if has_mode(GameEnums.FlightMode.NORMAL) else flight_modes[0]
