extends Node
## Global game state and settings (autoload "Game").

signal view_mode_changed(mode: int)
signal flight_mode_changed(mode: int)
signal view_lock_changed
signal quality_changed

const MAP_MANIFEST := "res://assets/maps/manifest.json"
const CREDITS_FILE := "res://assets/credits.json"
const SETTINGS_FILE := "user://settings.cfg"

const VM := GameEnums.ViewMode

var maps: Array[Dictionary] = []
var credits: Array[Dictionary] = []

var selected_map := 0
var selected_drone: StringName = &"mini5pro"
var view_mode: int = VM.THIRD_PERSON
var flight_mode: int = GameEnums.FlightMode.NORMAL
## 3rd person view turns with the drone (true) or stays world-fixed (false).
## FPV has no such option: there, looking steers the drone (PlayerRig).
var third_view_local := false
## FPV local view also follows drone pitch/roll (real goggles feel, less comfortable).
var fpv_follow_attitude := false
var is_vr := false
var quality: int = GameEnums.Quality.MEDIUM


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	maps = _load_json_array(MAP_MANIFEST)
	maps.append({"id": "test_field", "title": "Valley Town (built-in)", "scene": "", "surround": "ground"})
	credits = _load_json_array(CREDITS_FILE)
	_load_settings()


## Shown on the main menu. Bump application/config/version in project.godot
## with every change you hand over for testing.
func version_text() -> String:
	return "v" + str(ProjectSettings.get_setting("application/config/version", "?"))


func drone_spec() -> DroneSpec:
	return DroneCatalog.get_spec(selected_drone)


func current_map() -> Dictionary:
	if maps.is_empty():
		return {}
	return maps[clampi(selected_map, 0, maps.size() - 1)]


func set_drone(id: StringName) -> void:
	selected_drone = id
	var spec := drone_spec()
	if not spec.has_mode(flight_mode):
		flight_mode = spec.default_mode()
	if view_mode == VM.FLYER and not spec.allows_flyer:
		view_mode = VM.THIRD_PERSON


func available_views() -> Array[int]:
	var views: Array[int] = [VM.FPV, VM.THIRD_PERSON]
	if drone_spec().allows_flyer:
		views.append(VM.FLYER)
	return views


func set_view_mode(mode: int) -> void:
	if mode not in available_views():
		return
	view_mode = mode
	view_mode_changed.emit(mode)


func cycle_view_mode() -> void:
	var views := available_views()
	set_view_mode(views[(views.find(view_mode) + 1) % views.size()])


func set_flight_mode(mode: int) -> void:
	if not drone_spec().has_mode(mode):
		return
	flight_mode = mode
	flight_mode_changed.emit(mode)


func cycle_flight_mode() -> void:
	set_flight_mode(drone_spec().next_mode(flight_mode))


## Whether the current view turns with the drone.
func view_is_local() -> bool:
	match view_mode:
		VM.FPV:
			return true
		VM.THIRD_PERSON:
			return third_view_local
	return false


## Only 3rd person has a view lock (FPV always steers with the look).
func toggle_view_lock() -> void:
	if view_mode != VM.THIRD_PERSON:
		return
	third_view_local = not third_view_local
	view_lock_changed.emit()


func quality_settings() -> Dictionary:
	return GameEnums.QUALITY_SETTINGS[quality]


func cycle_quality(dir := 1) -> void:
	quality = posmod(quality + dir, GameEnums.QUALITY_NAMES.size())
	quality_changed.emit()


func credits_text() -> String:
	var lines: PackedStringArray = []
	var sections := {"map": "Worlds", "drone": "Drones", "pilot": "Pilot"}
	for kind: String in sections:
		var entries := credits.filter(func(c: Dictionary) -> bool: return c.get("kind") == kind)
		if entries.is_empty():
			continue
		lines.append("[b]%s[/b]" % sections[kind])
		for c: Dictionary in entries:
			lines.append("  " + Attribution.format_line(c))
		lines.append("")
	lines.append("[b]Licences[/b]")
	lines.append("  3D models are used under their creators' Sketchfab licences (shown above),")
	lines.append("  converted and split into chunks for VR. CC BY-SA works stay under CC BY-SA.")
	lines.append("  Valley Town and drones without an imported model are built in code.")
	lines.append("")
	lines.append("Made with Godot Engine (godotengine.org/license).")
	return "\n".join(lines)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "map", selected_map)
	cfg.set_value("game", "drone", String(selected_drone))
	cfg.set_value("game", "view", view_mode)
	cfg.set_value("game", "flight", flight_mode)
	cfg.set_value("game", "quality", quality)
	cfg.set_value("view", "third_local", third_view_local)
	cfg.set_value("view", "fpv_attitude", fpv_follow_attitude)
	cfg.save(SETTINGS_FILE)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_FILE) != OK:
		return
	selected_map = cfg.get_value("game", "map", selected_map)
	var drone := StringName(cfg.get_value("game", "drone", String(selected_drone)))
	if drone in DroneCatalog.ORDER:
		selected_drone = drone
	view_mode = cfg.get_value("game", "view", view_mode)
	flight_mode = cfg.get_value("game", "flight", flight_mode)
	quality = clampi(cfg.get_value("game", "quality", quality), 0, GameEnums.QUALITY_NAMES.size() - 1)
	third_view_local = cfg.get_value("view", "third_local", third_view_local)
	fpv_follow_attitude = cfg.get_value("view", "fpv_attitude", fpv_follow_attitude)
	set_drone(selected_drone)


static func _load_json_array(path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not FileAccess.file_exists(path):
		return out
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Array:
		for item: Variant in data:
			if item is Dictionary:
				out.append(item)
	return out
