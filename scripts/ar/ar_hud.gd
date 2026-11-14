class_name ARHud
extends CanvasLayer
## AR calibration + play overlay (mobile-first, big touch targets).
## Presentation only; ARSessionController owns the behaviour and feeds it a
## CalibrationFlow each frame through apply_flow().

signal lock_toggled(locked: bool)
signal magnify_toggled(enabled: bool)
signal recenter_pressed()
signal replace_pressed()
signal place_pressed()
signal place_in_front_pressed()
signal play_without_ar_pressed()
## Five quick taps on the step panel toggle the AR debug line.
signal debug_toggled(visible: bool)

const PRIMARY_SIZE: Vector2 = Vector2(260.0, 96.0)
const SECONDARY_SIZE: Vector2 = Vector2(170.0, 80.0)
const DEBUG_TAPS: int = 5
const DEBUG_TAP_WINDOW: float = 2.0

var title_label: Label
var status_label: Label
var stats_label: Label
var sweep_hint: Control
var place_button: Button
var place_in_front_button: Button
var play_without_ar_button: Button
var lock_button: Button
var unlock_button: Button
var magnify_button: Button
var recenter_button: Button
var replace_button: Button
var debug_label: Label
## Debug line shown because the player toggled it (5 taps on the panel).
var debug_requested: bool = false

var _sweep_phone: Panel
var _sweep_time: float = 0.0
var _banner: PanelContainer
var _tap_times: Array[float] = []
var _clock: float = 0.0


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
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	# Top: step title + live status on a dark banner so it reads over video.
	_banner = PanelContainer.new()
	# STOP so taps on the panel count toward the debug toggle and never
	# place the board by accident.
	_banner.mouse_filter = Control.MOUSE_FILTER_STOP
	_banner.gui_input.connect(_on_banner_input)
	_banner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.05, 0.08, 0.72)
	style.set_corner_radius_all(18)
	style.content_margin_left = 28.0
	style.content_margin_right = 28.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0
	_banner.add_theme_stylebox_override("panel", style)
	column.add_child(_banner)
	var banner_column := VBoxContainer.new()
	banner_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(banner_column)
	title_label = _label(banner_column, 30, Color(0.55, 0.95, 1.0))
	status_label = _label(banner_column, 24, Color.WHITE)
	stats_label = _label(banner_column, 18, Color(0.75, 0.8, 0.85))

	# Middle: animated "sweep side to side" phone glyph.
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	sweep_hint = Control.new()
	sweep_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sweep_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	spacer.add_child(sweep_hint)
	_sweep_phone = Panel.new()
	_sweep_phone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var phone_style := StyleBoxFlat.new()
	phone_style.bg_color = Color(1, 1, 1, 0.12)
	phone_style.border_color = Color(0.55, 0.95, 1.0, 0.9)
	phone_style.set_border_width_all(5)
	phone_style.set_corner_radius_all(14)
	_sweep_phone.add_theme_stylebox_override("panel", phone_style)
	_sweep_phone.size = Vector2(70.0, 120.0)
	sweep_hint.add_child(_sweep_phone)
	var arrows := Label.new()
	arrows.text = "<   sweep slowly   >"
	arrows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrows.add_theme_font_size_override("font_size", 24)
	arrows.add_theme_color_override("font_outline_color", Color.BLACK)
	arrows.add_theme_constant_override("outline_size", 6)
	arrows.position = Vector2(-120.0, 70.0)
	arrows.size = Vector2(240.0, 36.0)
	arrows.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sweep_hint.add_child(arrows)

	# Bottom: big buttons.
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	column.add_child(row)
	place_button = _button(row, "Place board", PRIMARY_SIZE, true)
	place_button.pressed.connect(func() -> void: place_pressed.emit())
	place_in_front_button = _button(row, "Place in front of me", PRIMARY_SIZE, true)
	place_in_front_button.pressed.connect(func() -> void: place_in_front_pressed.emit())
	play_without_ar_button = _button(row, "Play without AR", SECONDARY_SIZE, false)
	play_without_ar_button.pressed.connect(func() -> void: play_without_ar_pressed.emit())
	lock_button = _button(row, "Lock", PRIMARY_SIZE, true)
	lock_button.pressed.connect(func() -> void: lock_toggled.emit(true))
	unlock_button = _button(row, "Unlock", SECONDARY_SIZE, false)
	unlock_button.pressed.connect(func() -> void: lock_toggled.emit(false))
	replace_button = _button(row, "Re-place", SECONDARY_SIZE, false)
	replace_button.pressed.connect(func() -> void: replace_pressed.emit())
	recenter_button = _button(row, "Recenter", SECONDARY_SIZE, false)
	recenter_button.pressed.connect(func() -> void: recenter_pressed.emit())
	magnify_button = _button(row, "Magnify", SECONDARY_SIZE, false)
	magnify_button.toggle_mode = true
	magnify_button.toggled.connect(func(on: bool) -> void: magnify_toggled.emit(on))

	# Small AR diagnostics line, bottom-left, above everything else.
	debug_label = Label.new()
	debug_label.name = "ARDebug"
	debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	debug_label.offset_top = -118.0
	debug_label.offset_bottom = -4.0
	debug_label.offset_left = 8.0
	debug_label.offset_right = -8.0
	debug_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	debug_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	debug_label.add_theme_font_size_override("font_size", 15)
	debug_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.6))
	debug_label.add_theme_color_override("font_outline_color", Color.BLACK)
	debug_label.add_theme_constant_override("outline_size", 5)
	debug_label.visible = false
	add_child(debug_label)
	apply_flow(CalibrationFlow.new())


func _process(delta: float) -> void:
	_clock += delta
	if sweep_hint == null or not sweep_hint.visible:
		return
	_sweep_time += delta
	_sweep_phone.position = Vector2(sin(_sweep_time * 2.2) * 110.0 - 35.0, -60.0)


func _label(parent: Control, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(640.0, 0.0)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _button(parent: Control, text: String, min_size: Vector2, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = min_size
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 28 if primary else 22)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.1, 0.55, 0.75, 0.92) if primary else Color(0.08, 0.1, 0.14, 0.85)
	normal.set_corner_radius_all(20)
	normal.border_color = Color(0.55, 0.95, 1.0, 0.9)
	normal.set_border_width_all(2)
	normal.content_margin_left = 20.0
	normal.content_margin_right = 20.0
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = normal.bg_color.lightened(0.25)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", normal)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("hover_pressed", pressed)
	parent.add_child(button)
	return button


## Show the controls and text for the flow's current step.
func apply_flow(flow: CalibrationFlow) -> void:
	var shown: Dictionary = flow.controls()
	place_button.visible = bool(shown["place"])
	place_in_front_button.visible = bool(shown["place_in_front"])
	play_without_ar_button.visible = bool(shown["play_without_ar"])
	lock_button.visible = bool(shown["lock"])
	unlock_button.visible = bool(shown["unlock"])
	replace_button.visible = bool(shown["replace"])
	recenter_button.visible = bool(shown["recenter"])
	magnify_button.visible = bool(shown["magnify"])
	sweep_hint.visible = bool(shown["sweep_hint"])
	stats_label.visible = bool(shown["stats"])
	title_label.text = flow.title()
	title_label.visible = not title_label.text.is_empty()
	status_label.text = flow.message()
	_banner.visible = flow.is_calibrating()
	var info: Dictionary = flow.last_info
	stats_label.text = "Feature points: %d   ·   Surfaces: %d" % [int(info.get("points", 0)), int(info.get("upward_planes", 0))]


## Temporary status line (e.g. tracking lost while playing).
func set_status(text: String) -> void:
	status_label.text = text
	_banner.visible = not text.is_empty()


## True if a screen position lands on one of the AR buttons.
func is_over_ui(screen_position: Vector2) -> bool:
	for button: Button in [place_button, place_in_front_button, play_without_ar_button, lock_button, unlock_button, magnify_button, recenter_button, replace_button]:
		if button.visible and button.get_global_rect().has_point(screen_position):
			return true
	return _banner.visible and _banner.get_global_rect().has_point(screen_position)


## Set the debug text; `forced` shows it even if the player has not toggled it
## (e.g. after the scan timeout, or in a debuggable build).
func set_debug_text(text: String, forced: bool) -> void:
	debug_label.text = text
	debug_label.visible = (debug_requested or forced) and not text.is_empty()


## Count a tap on the step panel; DEBUG_TAPS within DEBUG_TAP_WINDOW toggle.
func register_panel_tap(now: float) -> bool:
	_tap_times.append(now)
	while not _tap_times.is_empty() and now - _tap_times[0] > DEBUG_TAP_WINDOW:
		_tap_times.pop_front()
	if _tap_times.size() >= DEBUG_TAPS:
		_tap_times.clear()
		debug_requested = not debug_requested
		debug_label.visible = debug_requested and not debug_label.text.is_empty()
		debug_toggled.emit(debug_requested)
		return true
	return false


func _on_banner_input(event: InputEvent) -> void:
	var pressed: bool = (
		(event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
		or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)
	)
	if pressed:
		register_panel_tap(_clock)
		_banner.accept_event()
