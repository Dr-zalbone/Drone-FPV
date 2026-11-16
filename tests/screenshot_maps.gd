extends SceneTree
## Desktop (non-headless) visual check. Saves to user://:
##   shot_<map>_<view>.png        each view, drone 30 m up
##   shot_<map>_rc.png            flyer view, turned 120 deg and looking down at the RC
##   godot --path . --script res://tests/screenshot_maps.gd [-- map_index]
func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	for i in 40:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("user://shot_%s.png" % name)


func _run() -> void:
	await process_frame
	var game: Node = root.get_node("Game")
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _shot("menu")
	var args := OS.get_cmdline_user_args()
	var indices: Array = range(game.maps.size()) if args.is_empty() else [int(args[0])]
	for m: int in indices:
		game.selected_map = m
		game.set_drone(&"mini5pro")
		game.view_mode = GameEnums.ViewMode.THIRD_PERSON
		main._start_game()
		while main.state != main.State.PLAYING:
			await process_frame
		var id: String = game.current_map().id
		var rig: Node = main.rig
		game.set_view_mode(GameEnums.ViewMode.FLYER)
		rig._desktop_yaw = deg_to_rad(120)
		rig._desktop_pitch = deg_to_rad(-55)
		await _shot(id + "_rc")
		print("%s cam yaw %.1f body yaw %.1f rig yaw %.1f" % [id, rad_to_deg(FlightMath.basis_yaw(rig.camera.transform.basis)), rad_to_deg(FlightMath.basis_yaw(rig.pilot_body.transform.basis)), rad_to_deg(FlightMath.basis_yaw(rig.global_basis))])
		main._drone.global_position += Vector3(0, 30, 0)
		for view in [GameEnums.ViewMode.THIRD_PERSON, GameEnums.ViewMode.FPV, GameEnums.ViewMode.FLYER]:
			game.set_view_mode(view)
			await _shot("%s_%d" % [id, view])
		main._exit_to_menu()
		for i in 5:
			await process_frame
	quit()
