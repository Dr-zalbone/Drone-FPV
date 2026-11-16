class_name Hud
extends Node3D
## Head-locked flight read-out plus short toast messages.

var drone: Drone
var origin_height := 0.0

var _label: Label3D
var _toast: Label3D
var _toast_time := 0.0
var _tick := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	position = Vector3(0, -0.28, -1.0)
	_label = _make_label(Vector3.ZERO, 22)
	_toast = _make_label(Vector3(0, 0.38, 0), 36)
	visible = false


func _make_label(pos: Vector3, font_size: int) -> Label3D:
	var l := Label3D.new()
	l.position = pos
	l.font_size = font_size
	l.pixel_size = 0.0012
	l.outline_size = 8
	l.no_depth_test = true
	l.fixed_size = false
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.render_priority = 10
	l.outline_render_priority = 9
	l.shaded = false
	add_child(l)
	return l


func toast(text: String, seconds := 2.0) -> void:
	_toast.text = text
	_toast.visible = true
	_toast_time = seconds


func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		if _toast_time <= 0.0:
			_toast.visible = false
	_tick -= delta
	if drone == null or not is_instance_valid(drone) or _tick > 0.0:
		return
	_tick = 0.1
	# In Flyer view the RC shows telemetry; keep the head clear.
	_label.visible = Game.view_mode != GameEnums.ViewMode.FLYER
	var v := drone.linear_velocity
	var lines := PackedStringArray([
		"%s  |  %s  |  %s" % [
			drone.spec.display_name,
			GameEnums.FLIGHT_NAMES[drone.flight_mode],
			GameEnums.VIEW_NAMES[Game.view_mode],
		],
		"SPD %4.1f m/s (%3d km/h)   ALT %5.1f m   VS %+4.1f" % [
			v.length(), int(v.length() * 3.6), drone.global_position.y - origin_height, v.y],
	])
	if Game.view_mode != GameEnums.ViewMode.FLYER:
		lines.append("View: " + ("turns with drone" if Game.view_is_local() else "world-fixed"))
	if drone.is_crashed:
		lines.append("CRASHED - press B / R to reset")
	_label.text = "\n".join(lines)
