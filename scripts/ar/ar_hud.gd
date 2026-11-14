class_name ARHud
extends CanvasLayer
## AR overlay: a status line plus Lock, Magnify, Recenter and Re-place.
## Presentation only; ARSessionController owns the behaviour.

signal lock_toggled(locked: bool)
signal magnify_toggled(enabled: bool)
signal recenter_pressed()
signal replace_pressed()

var status_label: Label
var lock_button: Button
var magnify_button: Button
var recenter_button: Button
var replace_button: Button


func _ready() -> void:
	layer = 4
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_END
	margin.add_child(column)
	status_label = Label.new()
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 22)
	status_label.add_theme_color_override("font_outline_color", Color.BLACK)
	status_label.add_theme_constant_override("outline_size", 6)
	column.add_child(status_label)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	lock_button = _button(row, "Lock")
	lock_button.toggle_mode = true
	lock_button.toggled.connect(func(on: bool) -> void:
		lock_button.text = "Locked" if on else "Lock"
		lock_toggled.emit(on))
	magnify_button = _button(row, "Magnify")
	magnify_button.toggle_mode = true
	magnify_button.toggled.connect(func(on: bool) -> void: magnify_toggled.emit(on))
	recenter_button = _button(row, "Recenter")
	recenter_button.pressed.connect(func() -> void: recenter_pressed.emit())
	replace_button = _button(row, "Re-place")
	replace_button.pressed.connect(func() -> void: replace_pressed.emit())
	set_placed(false)


func _button(parent: Control, text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(140.0, 64.0)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 20)
	parent.add_child(button)
	return button


func set_status(text: String) -> void:
	status_label.text = text


## Adjustment buttons only make sense once the diorama is placed.
func set_placed(placed: bool) -> void:
	for button: Button in [lock_button, magnify_button, recenter_button, replace_button]:
		button.visible = placed


func set_locked(locked: bool) -> void:
	lock_button.set_pressed_no_signal(locked)
	lock_button.text = "Locked" if locked else "Lock"


## True if a screen position lands on one of the AR buttons.
func is_over_ui(screen_position: Vector2) -> bool:
	for button: Button in [lock_button, magnify_button, recenter_button, replace_button]:
		if button.visible and button.get_global_rect().has_point(screen_position):
			return true
	return false
