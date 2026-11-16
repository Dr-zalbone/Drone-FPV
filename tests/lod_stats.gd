extends SceneTree
## Prints rendered triangles / draw calls per quality preset for each map
## (desktop, needs a window). godot --path . --script res://tests/lod_stats.gd
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var game: Node = root.get_node("Game")
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for m in game.maps.size() - 1:
		game.selected_map = m
		game.view_mode = GameEnums.ViewMode.THIRD_PERSON
		main._start_game()
		while main.state != main.State.PLAYING:
			await process_frame
		main._drone.global_position += Vector3(0, 60, 0)
		var rig: Node = main.rig
		rig._desktop_pitch = -0.3
		for q in [GameEnums.Quality.HIGH, GameEnums.Quality.MEDIUM, GameEnums.Quality.LOW]:
			game.quality = q
			game.quality_changed.emit()
			for i in 30:
				await process_frame
			var tris := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
			var calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
			print("%-26s %-18s tris %8d  draw calls %4d" % [game.current_map().id, GameEnums.QUALITY_NAMES[q], tris, calls])
		main._exit_to_menu()
		for i in 5:
			await process_frame
	quit()
