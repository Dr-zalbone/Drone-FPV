class_name MainMenu
extends MenuBase
## Startup / loading screen: world, drone and view selection plus the
## credits panel for every imported 3D model.

signal start_requested
signal quit_requested

var _setup_box: VBoxContainer
var _loading_box: VBoxContainer
var _loading_label: Label
var _progress: ProgressBar


func _ready() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 32)
	panel.add_child(columns)

	# Left: setup + loading.
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.25
	left.add_theme_constant_override("separation", 14)
	columns.add_child(left)
	left.add_child(make_label("DRONE FPV VR", 52, Color(0.35, 0.8, 1.0)))
	left.add_child(make_label("Quest 3S flight simulator", 24, Color(0.7, 0.7, 0.75)))

	_setup_box = VBoxContainer.new()
	_setup_box.add_theme_constant_override("separation", 12)
	_setup_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(_setup_box)
	add_cycler(_setup_box, "World", _map_name, _step_map)
	add_cycler(_setup_box, "Drone", func() -> String: return Game.drone_spec().display_name, _step_drone)
	add_cycler(_setup_box, "View", func() -> String: return GameEnums.VIEW_NAMES[Game.view_mode], _step_view)
	add_cycler(_setup_box, "Flight mode", func() -> String: return GameEnums.FLIGHT_NAMES[Game.flight_mode], _step_flight)
	add_cycler(_setup_box, "Graphics", func() -> String: return GameEnums.QUALITY_NAMES[Game.quality],
			func(dir: int) -> void: Game.cycle_quality(dir))
	add_toggle(_setup_box, "FPV view turns with drone",
			func() -> bool: return Game.fpv_view_local, func(on: bool) -> void: Game.fpv_view_local = on)
	add_toggle(_setup_box, "3rd person view turns with drone",
			func() -> bool: return Game.third_view_local, func(on: bool) -> void: Game.third_view_local = on)
	add_toggle(_setup_box, "FPV horizon tilts with drone (intense)",
			func() -> bool: return Game.fpv_follow_attitude, func(on: bool) -> void: Game.fpv_follow_attitude = on)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_setup_box.add_child(spacer)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	_setup_box.add_child(buttons)
	var start := add_button(buttons, "START FLIGHT", func() -> void: start_requested.emit())
	start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start.add_theme_font_size_override("font_size", 36)
	add_button(buttons, "Quit", func() -> void: quit_requested.emit()).custom_minimum_size = Vector2(160, 64)

	_loading_box = VBoxContainer.new()
	_loading_box.add_theme_constant_override("separation", 20)
	_loading_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_loading_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_loading_box.visible = false
	left.add_child(_loading_box)
	_loading_label = make_label("Loading...", 34)
	_loading_box.add_child(_loading_label)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(0, 40)
	_progress.max_value = 1.0
	_progress.step = 0.001
	_loading_box.add_child(_progress)
	_loading_box.add_child(make_label(_controls_help(), 22, Color(0.75, 0.78, 0.82)))

	# Right: credits.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	right.add_child(make_label("CREDITS", 34, Color(0.35, 0.8, 1.0)))
	var credits := RichTextLabel.new()
	credits.bbcode_enabled = true
	credits.size_flags_vertical = Control.SIZE_EXPAND_FILL
	credits.scroll_active = true
	credits.text = Game.credits_text()
	right.add_child(credits)
	refresh()


func show_loading(active: bool, text := "Loading...") -> void:
	_setup_box.visible = not active
	_loading_box.visible = active
	_loading_label.text = text
	_progress.value = 0.0


func set_progress(value: float, text := "") -> void:
	_progress.value = value
	if text != "":
		_loading_label.text = text


func _map_name() -> String:
	var entry := Game.current_map()
	return entry.get("title", "Test Field")


func _step_map(dir: int) -> void:
	var count := Game.maps.size()
	if count > 0:
		Game.selected_map = posmod(Game.selected_map + dir, count)


func _step_drone(dir: int) -> void:
	var ids := DroneCatalog.ORDER
	Game.set_drone(ids[posmod(ids.find(Game.selected_drone) + dir, ids.size())])


func _step_view(dir: int) -> void:
	var views := Game.available_views()
	Game.set_view_mode(views[posmod(views.find(Game.view_mode) + dir, views.size())])


func _step_flight(dir: int) -> void:
	var modes := Game.drone_spec().flight_modes
	Game.set_flight_mode(modes[posmod(modes.find(Game.flight_mode) + dir, modes.size())])


static func _controls_help() -> String:
	return "\n".join([
		"Left stick: throttle / yaw      Right stick: pitch / roll  (Mode 2)",
		"A: flight mode    B: reset drone    Y: change view    X: view lock",
		"Right grip: recenter view    Menu: pause",
		"Desktop: WASD + arrows, V view, M mode, L lock, R reset, Esc menu",
	])
