class_name PauseMenu
extends MenuBase
## In-flight menu.

signal resume_requested
signal reset_requested
signal exit_requested


func _ready() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(make_label("PAUSED", 44, Color(0.35, 0.8, 1.0)))
	add_cycler(box, "View", func() -> String: return GameEnums.VIEW_NAMES[Game.view_mode],
			func(_dir: int) -> void: Game.cycle_view_mode())
	add_cycler(box, "Flight mode", func() -> String: return GameEnums.FLIGHT_NAMES[Game.flight_mode],
			func(_dir: int) -> void: Game.cycle_flight_mode())
	add_cycler(box, "Graphics", func() -> String: return GameEnums.QUALITY_NAMES[Game.quality],
			func(dir: int) -> void: Game.cycle_quality(dir))
	add_cycler(box, "Foveation", func() -> String: return GameEnums.FOVEATION_NAMES[Game.foveation],
			func(dir: int) -> void: Game.cycle_foveation(dir))
	add_toggle(box, "3rd person view turns with drone",
			func() -> bool: return Game.third_view_local,
			func(on: bool) -> void:
				Game.third_view_local = on
				Game.view_lock_changed.emit())
	add_toggle(box, "FPV horizon tilts with drone",
			func() -> bool: return Game.fpv_follow_attitude,
			func(on: bool) -> void: Game.fpv_follow_attitude = on)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	for item: Array in [["Resume", resume_requested], ["Reset drone", reset_requested], ["Main menu", exit_requested]]:
		var sig: Signal = item[1]
		add_button(row, item[0], func() -> void: sig.emit()).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refresh()
