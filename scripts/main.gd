extends Node3D
## Entry point: XR start-up, lobby + menu, threaded map loading, spawning and
## routing controller / keyboard actions.

enum State { MENU, LOADING, PLAYING, PAUSED }

const VM := GameEnums.ViewMode
const TARGET_REFRESH_RATE := 90.0

var state := State.MENU
var rig: PlayerRig
var pointer: UIPointer
var menu_panel: Panel3D
var main_menu: MainMenu
var pause_panel: Panel3D
var pause_menu: PauseMenu

var _world: Node3D
var _lobby: Node3D
var _map: Node3D
var _drone: Drone
var _pilot: Node3D
var _loading_path := ""
var _xr: OpenXRInterface
var _env: Environment


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_init_xr()
	for node in WorldBuilder.make_environment():
		add_child(node)
		if node is WorldEnvironment:
			_env = (node as WorldEnvironment).environment
	_world = Node3D.new()
	_world.name = "World"
	_world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_world)

	rig = PlayerRig.new()
	rig.name = "PlayerRig"
	add_child(rig)
	rig.left_hand.button_pressed.connect(_on_left_button)
	rig.right_hand.button_pressed.connect(_on_right_button)
	rig.right_hand.button_released.connect(_on_right_released)

	pointer = UIPointer.new()
	pointer.rig = rig
	add_child(pointer)

	main_menu = MainMenu.new()
	main_menu.start_requested.connect(_start_game)
	main_menu.quit_requested.connect(func() -> void: get_tree().quit())
	menu_panel = Panel3D.new(main_menu, Vector2(2.0, 1.25), Vector2i(1600, 1000))
	add_child(menu_panel)

	pause_menu = PauseMenu.new()
	pause_menu.resume_requested.connect(_resume)
	pause_menu.reset_requested.connect(func() -> void:
		_resume()
		_reset_drone())
	pause_menu.exit_requested.connect(_exit_to_menu)
	pause_panel = Panel3D.new(pause_menu, Vector2(1.4, 1.0), Vector2i(1120, 800))
	pause_panel.visible = false
	add_child(pause_panel)

	Game.view_mode_changed.connect(_on_view_mode_changed)
	Game.flight_mode_changed.connect(_on_flight_mode_changed)
	Game.view_lock_changed.connect(_on_view_lock_changed)
	Game.quality_changed.connect(_apply_quality)
	_enter_lobby()
	_apply_quality()


# --------------------------------------------------------------------------
# XR
# --------------------------------------------------------------------------
func _init_xr() -> void:
	_xr = XRServer.find_interface("OpenXR") as OpenXRInterface
	if _xr and _xr.is_initialized():
		Game.is_vr = true
		get_viewport().use_xr = true
		# The headset paces frames; vsync on the desktop window would stall it.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		_xr.session_begun.connect(_on_xr_session_begun)
		_xr.pose_recentered.connect(_on_xr_recentered)
		print("OpenXR initialised")
	else:
		Game.is_vr = false
		print("OpenXR not available - desktop mode")


func _on_xr_session_begun() -> void:
	var rates := _xr.get_available_display_refresh_rates()
	if TARGET_REFRESH_RATE in rates:
		_xr.display_refresh_rate = TARGET_REFRESH_RATE
	var rate := _xr.display_refresh_rate if _xr.display_refresh_rate > 0.0 else TARGET_REFRESH_RATE
	Engine.physics_ticks_per_second = int(rate)


func _on_xr_recentered() -> void:
	XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, true)
	rig.recenter()


# --------------------------------------------------------------------------
# Quality / LOD
# --------------------------------------------------------------------------
## LOD system:
## 1. Maps are split into spatial chunks by tools/process_models.py, so each
##    chunk is frustum-culled on its own.
## 2. Godot's automatic mesh LODs (generated at import) are picked per chunk
##    from its screen-space size; mesh_lod_threshold sets how aggressive.
## 3. Chunks beyond the preset's view distance are culled (visibility range)
##    and depth fog hides the cut-off.
func _apply_quality() -> void:
	var q := Game.quality_settings()
	var vp := get_viewport()
	vp.mesh_lod_threshold = q.lod_threshold
	vp.msaa_3d = q.msaa
	if Game.is_vr and _xr:
		_xr.render_target_size_multiplier = q.render_scale
	var dist: float = q.view_distance
	rig.camera.far = dist + 100.0
	if _env:
		_env.fog_enabled = _map != null
		_env.fog_mode = Environment.FOG_MODE_DEPTH
		_env.fog_light_color = Color(0.72, 0.8, 0.9)
		_env.fog_density = 1.0
		_env.fog_depth_begin = dist * 0.55
		_env.fog_depth_end = dist
		_env.fog_depth_curve = 1.5
		_env.fog_sky_affect = 0.0
	if _map:
		for node in _map.find_children("*", "GeometryInstance3D", true, false):
			var gi := node as GeometryInstance3D
			var radius := 0.0
			if gi is VisualInstance3D:
				radius = (gi as VisualInstance3D).get_aabb().size.length() * 0.5
			gi.visibility_range_end = dist + radius
			gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED


# --------------------------------------------------------------------------
# Lobby / menu
# --------------------------------------------------------------------------
func _enter_lobby() -> void:
	state = State.MENU
	get_tree().paused = false
	_lobby = WorldBuilder.make_lobby()
	_world.add_child(_lobby)
	rig.enter_lobby(Transform3D.IDENTITY)
	rig.hud.visible = false
	menu_panel.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.45, -2.0))
	menu_panel.visible = true
	main_menu.show_loading(false)
	main_menu.refresh()
	pause_panel.visible = false
	_set_mouse_for_ui(true)


func _start_game() -> void:
	Game.save_settings()
	var entry := Game.current_map()
	main_menu.show_loading(true, "Loading %s..." % entry.get("title", "world"))
	state = State.LOADING
	_loading_path = entry.get("scene", "")
	if _loading_path == "":
		_finish_loading.call_deferred(WorldBuilder.make_test_field(), entry)
		return
	var err := ResourceLoader.load_threaded_request(_loading_path, "PackedScene", true)
	if err != OK:
		push_error("Cannot load %s (%s)" % [_loading_path, error_string(err)])
		main_menu.show_loading(false)
		state = State.MENU


func _process(_delta: float) -> void:
	if state == State.LOADING and _loading_path != "":
		var progress := []
		var status := ResourceLoader.load_threaded_get_status(_loading_path, progress)
		match status:
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				main_menu.set_progress(progress[0] if progress.size() > 0 else 0.0)
			ResourceLoader.THREAD_LOAD_LOADED:
				var packed := ResourceLoader.load_threaded_get(_loading_path) as PackedScene
				_loading_path = ""
				main_menu.set_progress(1.0, "Building world...")
				_finish_loading(packed.instantiate() as Node3D, Game.current_map())
			ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				push_error("Failed to load " + _loading_path)
				_loading_path = ""
				main_menu.show_loading(false)
				state = State.MENU


func _physics_process(_delta: float) -> void:
	if state == State.PLAYING and _drone:
		_drone.input = FlightInput.read(rig)


func _finish_loading(map: Node3D, entry: Dictionary) -> void:
	if _lobby:
		_lobby.queue_free()
		_lobby = null
	_map = map
	_map.name = "Map"
	_world.add_child(_map)
	# Let the physics server register the new collision shapes.
	await get_tree().physics_frame
	await get_tree().physics_frame

	var bounds := WorldBuilder.visual_bounds(_map)
	var space := get_world_3d().direct_space_state
	var pilot_xf: Transform3D
	if entry.has("spawn"):
		var s: Array = entry.spawn
		var at := Vector3(s[0], s[1], s[2])
		pilot_xf = Transform3D(Basis(Vector3.UP, WorldBuilder.open_yaw(space, at + Vector3(0, 1.6, 0))), at)
	else:
		pilot_xf = WorldBuilder.find_pilot_spawn(space, bounds)

	var spec := Game.drone_spec()
	# Drone sits on the ground a few metres in front of the pilot (-Z).
	var ahead := pilot_xf.origin + pilot_xf.basis * Vector3(0, 0, -(2.0 + spec.span * 1.5))
	var hit := WorldBuilder.ground_at(space, ahead + Vector3(0, 5, 0), bounds.position.y - 20.0)
	var ground_y: float = hit.position.y if not hit.is_empty() else pilot_xf.origin.y
	var drone_xf := Transform3D(pilot_xf.basis, Vector3(ahead.x, ground_y + spec.body_size.y * 0.5 + 0.05, ahead.z))

	_pilot = WorldBuilder.make_pilot()
	_world.add_child(_pilot)
	_pilot.global_transform = pilot_xf

	_drone = Drone.new()
	_world.add_child(_drone)
	_drone.setup(spec, drone_xf, bounds.position.y - 100.0)
	_drone.set_flight_mode(Game.flight_mode)
	_drone.crashed.connect(func() -> void: rig.hud.toast("CRASH! Press B / R to reset", 3.0))

	rig.drone = _drone
	rig.pilot_transform = pilot_xf
	rig.hud.drone = _drone
	rig.hud.origin_height = ground_y
	rig.hud.visible = true
	menu_panel.visible = false
	state = State.PLAYING
	_apply_quality()
	_apply_view_mode()
	_set_mouse_for_ui(false)
	rig.hud.toast("%s - %s" % [spec.display_name, GameEnums.FLIGHT_NAMES[_drone.flight_mode]], 3.0)


func _exit_to_menu() -> void:
	get_tree().paused = false
	if _drone:
		_drone.queue_free()
		_drone = null
	if _pilot:
		_pilot.queue_free()
		_pilot = null
	if _map:
		_map.queue_free()
		_map = null
	_enter_lobby()
	_apply_quality()


# --------------------------------------------------------------------------
# In-flight actions
# --------------------------------------------------------------------------
func _apply_view_mode() -> void:
	rig.set_view_mode(Game.view_mode)
	if _pilot:
		_pilot.visible = Game.view_mode != VM.FLYER


func _on_view_mode_changed(_mode: int) -> void:
	if state in [State.PLAYING, State.PAUSED]:
		_apply_view_mode()
		rig.hud.toast("View: " + GameEnums.VIEW_NAMES[Game.view_mode])


func _on_flight_mode_changed(mode: int) -> void:
	if _drone:
		_drone.set_flight_mode(mode)
		rig.hud.toast("Mode: " + GameEnums.FLIGHT_NAMES[mode])


func _on_view_lock_changed() -> void:
	if _drone:
		rig.recenter()
		rig.hud.toast("View " + ("turns with drone" if Game.view_is_local() else "world-fixed"))


func _reset_drone() -> void:
	if _drone:
		_drone.reset_to_spawn()
		rig.recenter()
		rig.hud.toast("Drone reset")


func _pause() -> void:
	if state != State.PLAYING:
		return
	state = State.PAUSED
	get_tree().paused = true
	pause_menu.refresh()
	pause_panel.visible = true
	pause_panel.face_camera(rig.camera, 1.4, 0.1)
	_set_mouse_for_ui(true)


func _resume() -> void:
	if state != State.PAUSED:
		return
	state = State.PLAYING
	get_tree().paused = false
	pause_panel.visible = false
	_set_mouse_for_ui(false)
	Game.save_settings()


func _toggle_pause() -> void:
	if state == State.PLAYING:
		_pause()
	elif state == State.PAUSED:
		_resume()


func _set_mouse_for_ui(ui: bool) -> void:
	if Game.is_vr:
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if ui else Input.MOUSE_MODE_CAPTURED


# --------------------------------------------------------------------------
# Input routing
# --------------------------------------------------------------------------
func _handle_action(action: StringName) -> void:
	match action:
		&"pause_menu":
			_toggle_pause()
		&"cycle_view":
			if state == State.PLAYING:
				Game.cycle_view_mode()
		&"cycle_flight_mode":
			if state == State.PLAYING:
				Game.cycle_flight_mode()
		&"toggle_view_lock":
			if state == State.PLAYING:
				Game.toggle_view_lock()
		&"reset_drone":
			if state == State.PLAYING:
				_reset_drone()
		&"recenter":
			rig.recenter()


func _on_left_button(button: String) -> void:
	match button:
		"menu_button":
			_handle_action(&"pause_menu")
		"by_button":
			_handle_action(&"cycle_view")
		"ax_button":
			_handle_action(&"toggle_view_lock")


func _on_right_button(button: String) -> void:
	match button:
		"trigger_click":
			pointer.click(true)
		"ax_button":
			_handle_action(&"cycle_flight_mode")
		"by_button":
			_handle_action(&"reset_drone")
		"grip_click":
			_handle_action(&"recenter")


func _on_right_released(button: String) -> void:
	if button == "trigger_click":
		pointer.click(false)


func _unhandled_input(event: InputEvent) -> void:
	for action: StringName in [&"pause_menu", &"cycle_view", &"cycle_flight_mode", &"toggle_view_lock", &"reset_drone"]:
		if event.is_action_pressed(action):
			_handle_action(action)
			get_viewport().set_input_as_handled()
			return
	if Game.is_vr:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rig.desktop_look((event as InputEventMouseMotion).relative)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			if mb.button_index == MOUSE_BUTTON_LEFT:
				pointer.click(mb.pressed)
			elif mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				pointer.scroll(mb.button_index == MOUSE_BUTTON_WHEEL_UP)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_MIDDLE:
			rig.recenter()
