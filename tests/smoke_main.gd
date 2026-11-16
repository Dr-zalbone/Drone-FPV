extends SceneTree
## Runs the real main scene headless through a whole session for each map:
## menu -> load -> every view mode / drone -> pause -> back to menu.
##   godot --headless --path . --script res://tests/smoke_main.gd [-- map_index]

var _errors := 0


func _initialize() -> void:
	_run.call_deferred()


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame


func _run() -> void:
	await process_frame
	var game: Node = root.get_node("Game")
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _wait(5)
	var args := OS.get_cmdline_user_args()
	var indices: Array = range(game.maps.size()) if args.is_empty() else [int(args[0])]
	for map_index: int in indices:
		for drone_id: StringName in DroneCatalog.ORDER:
			game.selected_map = map_index
			game.set_drone(drone_id)
			game.view_mode = GameEnums.ViewMode.THIRD_PERSON
			var t0 := Time.get_ticks_msec()
			main._start_game()
			while main.state != main.State.PLAYING:
				await process_frame
				if Time.get_ticks_msec() - t0 > 300000:
					printerr("FAIL: load timeout")
					quit(1)
					return
			var drone: Drone = main._drone
			print("map %s drone %s loaded in %d ms, spawn %s" % [
				game.current_map().get("id"), drone_id, Time.get_ticks_msec() - t0, drone.global_position])
			drone.input = Vector4(0, 1, 0, 0.5)
			for view: int in game.available_views():
				game.set_view_mode(view)
				await _wait(30)
			game.cycle_flight_mode()
			game.toggle_view_lock()
			await _wait(30)
			print("   after flight: pos %s crashed %s" % [drone.global_position, drone.is_crashed])
			main._pause()
			await _wait(3)
			main._resume()
			main._reset_drone()
			await _wait(3)
			main._exit_to_menu()
			await _wait(5)
	print("SMOKE DONE")
	quit(0)
