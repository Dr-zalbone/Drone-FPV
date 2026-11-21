extends SceneTree
## Debug: prints each map's pilot spawn, facing and the direction to the map centre.
##   godot --headless --path . --script res://tests/spawn_probe.gd [-- map_index]
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var game: Node = root.get_node("Game")
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	var args := OS.get_cmdline_user_args()
	var indices: Array = range(game.maps.size()) if args.is_empty() else [int(args[0])]
	for m: int in indices:
		game.selected_map = m
		main._start_game()
		while main.state != main.State.PLAYING:
			await process_frame
		var xf: Transform3D = main.rig.pilot_transform
		var bounds := WorldBuilder.visual_bounds(main._map)
		var c := bounds.get_center()
		var to_c := Vector3(c.x - xf.origin.x, 0, c.z - xf.origin.z)
		var fwd := -xf.basis.z
		print("%s: pilot %s  bounds y %.1f..%.1f  facing.dot(to_centre)=%.2f  dist to centre %.1f m" % [
			game.current_map().id, xf.origin, bounds.position.y, bounds.end.y,
			fwd.dot(to_c.normalized()), to_c.length()])
		main._exit_to_menu()
		for i in 5:
			await process_frame
	quit()
