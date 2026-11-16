class_name FlightInput
extends RefCounted
## Mode 2 stick mapping: left = throttle (Y) + yaw (X), right = pitch (Y) + roll (X).
## Combines Quest controllers with keyboard / gamepad (desktop testing).


## Returns Vector4(yaw, throttle, roll, pitch), each in [-1, 1].
static func read(rig: PlayerRig) -> Vector4:
	var yaw := Input.get_axis(&"yaw_left", &"yaw_right")
	var throttle := Input.get_axis(&"throttle_down", &"throttle_up")
	var roll := Input.get_axis(&"roll_left", &"roll_right")
	var pitch := Input.get_axis(&"pitch_back", &"pitch_forward")
	if Game.is_vr and rig != null:
		var l := rig.left_hand.get_vector2(&"primary")
		var r := rig.right_hand.get_vector2(&"primary")
		yaw += l.x
		throttle += l.y
		roll += r.x
		pitch += r.y
	return Vector4(
		FlightMath.shape_axis(clampf(yaw, -1, 1)),
		FlightMath.shape_axis(clampf(throttle, -1, 1), 0.08, 0.0),
		FlightMath.shape_axis(clampf(roll, -1, 1)),
		FlightMath.shape_axis(clampf(pitch, -1, 1)),
	)
