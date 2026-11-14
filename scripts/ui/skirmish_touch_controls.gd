class_name SkirmishTouchControls
extends CanvasLayer
## Tier 4 overlay: virtual joystick (left), Attack and Auto-resolve (right),
## and a status line. Pure input/presentation; SkirmishPossessionController
## turns it into CommandService orders.

signal auto_resolve_pressed()

var joystick: VirtualJoystick
var attack_button: Button
var auto_button: Button
var status_label: Label
## True while the Attack button is held down (touch or mouse).
var attack_held: bool = false


func _ready() -> void:
	layer = 5
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 28)
	add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)
	status_label = Label.new()
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 22)
	status_label.add_theme_color_override("font_outline_color", Color.BLACK)
	status_label.add_theme_constant_override("outline_size", 6)
	# Leave room for the desktop HUD rows above.
	status_label.custom_minimum_size = Vector2(0.0, 150.0)
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	column.add_child(status_label)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	var bottom := HBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(bottom)
	joystick = VirtualJoystick.new()
	bottom.add_child(joystick)
	var gap := Control.new()
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(gap)
	var buttons := VBoxContainer.new()
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 12)
	bottom.add_child(buttons)
	auto_button = _make_button("Auto-resolve (Esc)", Vector2(180.0, 56.0))
	auto_button.pressed.connect(func() -> void: auto_resolve_pressed.emit())
	buttons.add_child(auto_button)
	attack_button = _make_button("Attack (F)", Vector2(180.0, 110.0))
	attack_button.button_down.connect(func() -> void: attack_held = true)
	attack_button.button_up.connect(func() -> void: attack_held = false)
	buttons.add_child(attack_button)
	visibility_changed.connect(_on_visibility_changed)


func _make_button(text: String, min_size: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = min_size
	# Keyboard keys (Space, Enter) must never trigger these by focus.
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 20)
	return button


func set_status(text: String) -> void:
	status_label.text = text


## True if a screen position lands on the joystick or a button (so camera
## drags ignore it).
func is_over_controls(screen_position: Vector2) -> bool:
	for control: Control in [joystick, attack_button, auto_button]:
		if control.get_global_rect().has_point(screen_position):
			return true
	return false


func _on_visibility_changed() -> void:
	if not visible:
		attack_held = false
		if joystick != null:
			joystick.release()
