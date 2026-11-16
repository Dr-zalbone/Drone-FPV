extends SceneTree
## Headless unit tests. Run:
##   godot --headless --path . --script res://tests/run_tests.gd

var _passed := 0
var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	_test_attribution()
	_test_shape_axis()
	_test_drone_catalog()
	_test_desired_velocity()
	_test_target_attitude()
	_test_attitude_correction()
	_test_manual_throttle()
	_test_orbit()
	_test_game_views()
	_test_quality()
	_test_pilot_body()
	_test_map_lod()
	_test_facade_detail()
	await _test_drone_physics()
	print("\nRESULT: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: " + label)


func near(a: float, b: float, eps := 0.001) -> bool:
	return absf(a - b) <= eps


func _test_attribution() -> void:
	var a := Attribution.parse("cathedral_attribution-patrix_on_sketchfab.glb")
	check(a.title == "Cathedral" and a.author == "patrix" and a.site == "Sketchfab", "attribution cathedral %s" % a)
	var b := Attribution.parse("new_york_city._manhattan_attribiution-truekit_on_sketchfab.glb")
	check(b.title == "New York City Manhattan" and b.author == "truekit", "attribution misspelled %s" % b)
	var c := Attribution.parse("eze_village_-_france_attribution-Azad_Balabanian_on_sketchfab.glb")
	check(c.title == "Eze Village - France" and c.author == "Azad Balabanian", "attribution eze %s" % c)
	check(Attribution.parse("icon.svg").is_empty(), "attribution none")


func _test_shape_axis() -> void:
	check(FlightMath.shape_axis(0.05) == 0.0, "deadzone")
	check(near(FlightMath.shape_axis(1.0), 1.0), "full deflection")
	check(near(FlightMath.shape_axis(-1.0), -1.0), "full negative")
	check(FlightMath.shape_axis(0.5) < 0.5 and FlightMath.shape_axis(0.5) > 0.0, "expo softens centre")


func _test_drone_catalog() -> void:
	var mini := DroneCatalog.get_spec(&"mini5pro")
	var fpv := DroneCatalog.get_spec(&"dji_fpv")
	var cart := DroneCatalog.get_spec(&"flycart")
	var fm := GameEnums.FlightMode
	check(fpv.flight_modes == [fm.NORMAL, fm.SPORT, fm.MANUAL], "FPV has normal/sport/manual")
	check(not mini.has_mode(fm.MANUAL) and not cart.has_mode(fm.MANUAL), "only FPV has manual")
	check(cart.mass > 10.0 * fpv.mass and fpv.mass > mini.mass, "mass ordering")
	var n := fm.NORMAL
	check(cart.mode_params(n).max_speed < mini.mode_params(n).max_speed, "flycart slower than mini")
	check(fpv.mode_params(fm.SPORT).max_speed > mini.mode_params(fm.SPORT).max_speed, "fpv fastest")
	check(cart.mode_params(n).accel < fpv.mode_params(n).accel, "flycart sluggish")
	check(mini.mode_params(fm.CINE).max_speed < mini.mode_params(n).max_speed, "cine slow")
	check(not fpv.allows_flyer and mini.allows_flyer and cart.allows_flyer, "flyer view only for mini/flycart")
	check(fpv.next_mode(fm.MANUAL) == fm.NORMAL, "mode cycling wraps")


func _test_desired_velocity() -> void:
	var p := DroneCatalog.get_spec(&"mini5pro").mode_params(GameEnums.FlightMode.NORMAL)
	var fwd := FlightMath.desired_velocity(0.0, 0.0, 1.0, 0.0, p)
	check(near(fwd.z, -10.0) and near(fwd.x, 0.0), "pitch forward -> -Z %s" % fwd)
	var right := FlightMath.desired_velocity(0.0, 1.0, 0.0, 0.0, p)
	check(near(right.x, 10.0), "roll right -> +X")
	var turned := FlightMath.desired_velocity(PI / 2.0, 0.0, 1.0, 0.0, p)
	check(near(turned.x, -10.0, 0.01), "yawed 90 deg left -> forward is -X %s" % turned)
	var up := FlightMath.desired_velocity(0.0, 0.0, 0.0, 1.0, p)
	check(near(up.y, 5.0), "throttle up climbs")
	var diag := FlightMath.desired_velocity(0.0, 1.0, 1.0, 0.0, p)
	check(Vector2(diag.x, diag.z).length() <= 10.001, "diagonal capped")
	var acc := FlightMath.velocity_accel(Vector3.ZERO, Vector3(0, 0, -100), p)
	check(near(Vector2(acc.x, acc.z).length(), p.accel), "accel capped")


func _test_target_attitude() -> void:
	var b := FlightMath.target_attitude(0.0, Vector3(0, 0, -5), 30.0)
	check((-b.z).y < -0.05, "forward accel pitches nose down")
	var r := FlightMath.target_attitude(0.0, Vector3(5, 0, 0), 30.0)
	check(r.x.y < -0.05, "right accel lowers right side")
	var capped := FlightMath.target_attitude(0.0, Vector3(0, 0, -1000), 20.0)
	check(near(acos(capped.y.dot(Vector3.UP)), deg_to_rad(20.0), 0.01), "tilt capped")
	check(near(FlightMath.basis_yaw(Basis(Vector3.UP, 1.2)), 1.2), "basis_yaw round trip")


func _test_attitude_correction() -> void:
	var w := FlightMath.attitude_correction(Basis.IDENTITY, Basis(Vector3.UP, 0.5), 2.0)
	check(near(w.y, 1.0, 0.01), "yaw correction %s" % w)
	check(FlightMath.attitude_correction(Basis.IDENTITY, Basis.IDENTITY, 2.0) == Vector3.ZERO, "no error -> zero")


func _test_manual_throttle() -> void:
	check(near(FlightMath.manual_throttle(0.0, 4.0), 0.25), "centre = hover")
	check(near(FlightMath.manual_throttle(1.0, 4.0), 1.0), "top = max")
	check(near(FlightMath.manual_throttle(-1.0, 4.0), 0.0), "bottom = idle")


func _test_orbit() -> void:
	var target := Vector3(10, 5, 0)
	var p := FlightMath.orbit_camera_position(target, Basis.IDENTITY, Basis.IDENTITY, 3.0)
	check(p.is_equal_approx(Vector3(10, 5, 3)), "looking forward puts camera behind %s" % p)
	var left := FlightMath.orbit_camera_position(target, Basis.IDENTITY, Basis(Vector3.UP, PI / 2.0), 3.0)
	check(left.is_equal_approx(Vector3(13, 5, 0)), "turning head left orbits %s" % left)
	var down := FlightMath.orbit_camera_position(target, Basis.IDENTITY, Basis(Vector3.RIGHT, -PI / 4.0), 3.0)
	check(down.y > target.y, "looking down raises camera")


func _test_game_views() -> void:
	var game: Node = root.get_node("Game")
	game.set_drone(&"dji_fpv")
	check(GameEnums.ViewMode.FLYER not in game.available_views(), "no flyer for FPV drone")
	check(game.flight_mode in game.drone_spec().flight_modes, "flight mode valid after drone change")
	game.set_drone(&"flycart")
	game.set_flight_mode(GameEnums.FlightMode.MANUAL)
	check(game.flight_mode != GameEnums.FlightMode.MANUAL, "flycart rejects manual")
	game.set_drone(&"mini5pro")
	check(GameEnums.ViewMode.FLYER in game.available_views(), "flyer for mini")


func _test_quality() -> void:
	var game: Node = root.get_node("Game")
	var start: int = game.quality
	for i in GameEnums.QUALITY_NAMES.size():
		game.cycle_quality()
	check(game.quality == start, "quality cycle wraps")
	var low: Dictionary = GameEnums.QUALITY_SETTINGS[GameEnums.Quality.LOW]
	var high: Dictionary = GameEnums.QUALITY_SETTINGS[GameEnums.Quality.HIGH]
	check(low.lod_threshold > high.lod_threshold and low.view_distance < high.view_distance, "low preset is cheaper")


func _test_pilot_body() -> void:
	var head := Node3D.new()
	root.add_child(head)
	var body := PilotBody.new()
	body.head = head
	root.add_child(body)
	# Head turned 90 deg left and pitched 60 deg down, standing 1.7 m tall.
	head.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-60), PI / 2.0, 0)), Vector3(0.1, 1.7, 0.2))
	body.snap_to_head()
	check(near(FlightMath.basis_yaw(body.transform.basis), PI / 2.0), "body follows head yaw")
	check(body.transform.basis.y.dot(Vector3.UP) > 0.999, "body ignores head pitch/roll")
	check(near(body.position.x, 0.1) and near(body.position.z, 0.2) and near(body.position.y, 0.0), "body stands under head")
	var rc := body.rc_holder.global_position
	var to_rc := (rc - head.global_position).normalized()
	check(to_rc.dot(-head.global_basis.z) > 0.9, "RC is where you look when looking down (%.2f)" % to_rc.dot(-head.global_basis.z))
	body.queue_free()
	head.queue_free()


func _test_map_lod() -> void:
	check(MapLod.parse_name("nyc_chunk_3_4_lod2") == ["nyc_chunk_3_4", 2], "parse lod name")
	check(MapLod.parse_name("Ground")[1] == -1, "non-lod node")
	var sw := MapLod.switch_distances(186.0, 1.0)
	check(near(sw[0], 558.0) and near(sw[1], 1395.0), "switch distances %s" % [sw])
	check(MapLod.switch_distances(10.0, 1.0)[0] == MapLod.MIN_SWITCH, "min switch distance")
	check(MapLod.switch_distances(186.0, 0.6)[0] < sw[0], "low quality switches sooner")
	var r0 := MapLod.range_for(0, 2, sw, 1500.0, 50.0)
	var r1 := MapLod.range_for(1, 2, sw, 1500.0, 50.0)
	var r2 := MapLod.range_for(2, 2, sw, 1500.0, 50.0)
	check(r0 == Vector2(0, sw[0]) and r1 == Vector2(sw[0], sw[1]) and r2 == Vector2(sw[1], 1550.0), "contiguous ranges")
	check(MapLod.range_for(0, 0, sw, 1500.0, 50.0) == Vector2(0, 1550.0), "single-LOD chunk spans to view distance")


func _test_facade_detail() -> void:
	var root_node := Node3D.new()
	var textured := StandardMaterial3D.new()
	textured.albedo_texture = ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	var plain := StandardMaterial3D.new()
	for mat in [textured, textured, plain]:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.material = mat
		mi.mesh = box
		root_node.add_child(mi)
	check(FacadeDetail.apply(root_node) == 2, "only textured surfaces converted")
	var a := (root_node.get_child(0) as MeshInstance3D).get_surface_override_material(0) as ShaderMaterial
	var b := (root_node.get_child(1) as MeshInstance3D).get_surface_override_material(0) as ShaderMaterial
	check(a != null and a == b, "converted material shared")
	check(a.get_shader_parameter(&"albedo_tex") == textured.albedo_texture, "keeps original texture")
	check((root_node.get_child(2) as MeshInstance3D).get_surface_override_material(0) == null, "untextured untouched")
	root_node.free()


## Integration: drone hovers, climbs and moves forward in a real physics world.
func _test_drone_physics() -> void:
	var world := WorldBuilder.make_test_field()
	root.add_child(world)
	var drone := Drone.new()
	root.add_child(drone)
	drone.setup(DroneCatalog.get_spec(&"mini5pro"), Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 0)), -100.0)
	drone.input = Vector4(0, 1, 0, 0)  # climb
	for i in 90:
		await physics_frame
	check(drone.global_position.y > 2.0, "drone climbs (y=%.2f)" % drone.global_position.y)
	drone.input = Vector4(0, 0, 0, 1)  # forward
	for i in 120:
		await physics_frame
	check(drone.global_position.z < -5.0, "drone flies forward (z=%.2f)" % drone.global_position.z)
	check(not drone.is_crashed, "no false crash")
	var y := drone.global_position.y
	drone.input = Vector4.ZERO
	for i in 180:
		await physics_frame
	check(drone.linear_velocity.length() < 0.5, "angle mode brakes to hover (v=%.2f)" % drone.linear_velocity.length())
	check(absf(drone.global_position.y - y) < 1.0, "holds altitude")
	check(drone.global_basis.y.dot(Vector3.UP) > 0.99, "levels out")
	# Manual mode: centred throttle ~ hover, full roll flips the drone.
	drone.spec = DroneCatalog.get_spec(&"dji_fpv")
	drone.set_flight_mode(GameEnums.FlightMode.MANUAL)
	drone.input = Vector4(0, 0, 1, 0)
	for i in 30:
		await physics_frame
	check(drone.global_basis.y.dot(Vector3.UP) < 0.9, "manual roll rotates freely")
	drone.queue_free()
	world.queue_free()
