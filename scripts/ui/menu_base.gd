class_name MenuBase
extends Control
## Shared VR-friendly widgets: big buttons and "< value >" cyclers instead of
## popups (popups are awkward with a laser pointer).

var _refreshers: Array[Callable] = []


func _init() -> void:
	theme = make_theme()


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 30
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.06, 0.07, 0.09, 0.92)
	panel.set_corner_radius_all(24)
	panel.set_content_margin_all(28)
	t.set_stylebox("panel", "PanelContainer", panel)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.16, 0.18, 0.22)
	normal.set_corner_radius_all(12)
	normal.set_content_margin_all(12)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.22, 0.42, 0.62)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.12, 0.55, 0.85)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.1, 0.1, 0.12)
	for type in ["Button", "CheckButton"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("hover_pressed", type, pressed)
		t.set_stylebox("disabled", type, disabled)
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.15, 0.15, 0.18)
	bar_bg.set_corner_radius_all(8)
	var bar_fill := bar_bg.duplicate() as StyleBoxFlat
	bar_fill.bg_color = Color(0.12, 0.6, 0.9)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	t.set_font_size("normal_font_size", "RichTextLabel", 22)
	t.set_font_size("bold_font_size", "RichTextLabel", 24)
	return t


func refresh() -> void:
	for r in _refreshers:
		r.call()


func make_label(text: String, size := 30, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func add_button(parent: Container, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 64)
	b.pressed.connect(func() -> void:
		on_press.call()
		refresh())
	parent.add_child(b)
	return b


## Row "Label   [<]  value  [>]". step(dir) is called with -1 / +1.
func add_cycler(parent: Container, label: String, value: Callable, step: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var name_label := make_label(label, 28, Color(0.7, 0.75, 0.8))
	name_label.custom_minimum_size = Vector2(190, 0)
	row.add_child(name_label)
	add_button(row, "<", func() -> void: step.call(-1)).custom_minimum_size = Vector2(64, 64)
	var value_label := make_label("", 30)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.clip_text = true
	row.add_child(value_label)
	add_button(row, ">", func() -> void: step.call(1)).custom_minimum_size = Vector2(64, 64)
	parent.add_child(row)
	_refreshers.append(func() -> void: value_label.text = str(value.call()))


func add_toggle(parent: Container, label: String, getter: Callable, setter: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = label
	c.add_theme_font_size_override("font_size", 26)
	c.custom_minimum_size = Vector2(0, 56)
	c.toggled.connect(func(on: bool) -> void:
		setter.call(on)
		refresh())
	parent.add_child(c)
	_refreshers.append(func() -> void: c.set_pressed_no_signal(getter.call()))
	return c
