class_name DroneCatalog
extends RefCounted
## The three supported drones. Numbers are tuned for feel, loosely based on
## DJI published specs.

const MODEL_DIR := "res://assets/drones/"
const ORDER: Array[StringName] = [&"mini5pro", &"dji_fpv", &"flycart"]

const FM := GameEnums.FlightMode


static func all() -> Array[DroneSpec]:
	var out: Array[DroneSpec] = []
	for id in ORDER:
		out.append(get_spec(id))
	return out


static func get_spec(id: StringName) -> DroneSpec:
	var s := DroneSpec.new()
	s.id = id
	match id:
		&"mini5pro":
			# 249 g, very steady, cinematic. Cine / Normal / Sport.
			s.display_name = "DJI Mini 5 Pro"
			s.mass = 0.249
			s.body_size = Vector3(0.2, 0.07, 0.25)
			s.span = 0.25
			s.body_color = Color(0.55, 0.56, 0.58)
			s.camera_offset = Vector3(0, -0.02, -0.13)
			s.third_person_distance = 1.6
			s.third_person_height = 0.25
			s.allows_flyer = true
			s.crash_speed = 4.0
			s.flight_modes = [FM.CINE, FM.NORMAL, FM.SPORT]
			s.angle_modes = {
				FM.CINE: _angle(4.0, 2.0, 1.5, 25.0, 12.0, 2.5, 0.9, 3.0),
				FM.NORMAL: _angle(10.0, 5.0, 3.5, 60.0, 25.0, 6.0, 0.45, 4.0),
				FM.SPORT: _angle(18.0, 6.0, 5.0, 100.0, 35.0, 10.0, 0.3, 5.0),
			}
		&"dji_fpv":
			# 795 g, very fast, light and acrobatic. Normal / Sport / Manual.
			s.display_name = "DJI FPV"
			s.mass = 0.795
			s.body_size = Vector3(0.18, 0.12, 0.3)
			s.span = 0.32
			s.body_color = Color(0.12, 0.12, 0.13)
			s.camera_offset = Vector3(0, 0.03, -0.17)
			s.camera_tilt_deg = 20.0
			s.third_person_distance = 2.0
			s.third_person_height = 0.35
			s.allows_flyer = false  # flown from the goggles
			s.crash_speed = 8.0
			s.flight_modes = [FM.NORMAL, FM.SPORT, FM.MANUAL]
			s.angle_modes = {
				FM.NORMAL: _angle(15.0, 8.0, 5.0, 120.0, 30.0, 12.0, 0.3, 7.0),
				FM.SPORT: _angle(27.0, 15.0, 10.0, 200.0, 45.0, 20.0, 0.2, 9.0),
			}
			s.manual_rates_deg = Vector3(600, 400, 650)
			s.manual_thrust_to_weight = 4.5
			s.manual_max_speed = 39.0
		&"flycart":
			# ~65 kg delivery heavy-lifter: slow and sluggish. Normal / Sport.
			s.display_name = "DJI FlyCart 30"
			s.mass = 65.0
			s.body_size = Vector3(1.0, 0.6, 1.0)
			s.span = 2.8
			s.rotor_count = 8
			s.body_color = Color(0.85, 0.85, 0.82)
			s.camera_offset = Vector3(0, -0.1, -0.55)
			s.third_person_distance = 7.0
			s.third_person_height = 1.5
			s.allows_flyer = true
			s.crash_speed = 3.0
			s.flight_modes = [FM.NORMAL, FM.SPORT]
			s.angle_modes = {
				FM.NORMAL: _angle(5.0, 2.0, 1.5, 25.0, 10.0, 1.2, 1.6, 1.8),
				FM.SPORT: _angle(10.0, 3.0, 2.5, 35.0, 15.0, 2.0, 1.2, 2.2),
			}
		_:
			push_error("Unknown drone id %s" % id)
			return get_spec(&"mini5pro")
	var model := MODEL_DIR + String(id) + ".glb"
	if ResourceLoader.exists(model):
		s.model_path = model
	return s


## max_speed m/s, climb/descent m/s, yaw deg/s, max tilt deg,
## accel m/s^2 (cap), response s (velocity time constant), attitude gain 1/s.
static func _angle(max_speed: float, climb: float, descent: float, yaw_deg: float,
		tilt_deg: float, accel: float, response: float, attitude_gain: float) -> Dictionary:
	return {
		"max_speed": max_speed,
		"max_climb": climb,
		"max_descent": descent,
		"yaw_rate_deg": yaw_deg,
		"max_tilt_deg": tilt_deg,
		"accel": accel,
		"response": response,
		"attitude_gain": attitude_gain,
	}
