class_name VirtualJoystick
extends Control
## On-screen thumb stick for Tier 4. Works with real touch and with the mouse
## (via `input_devices/pointing/emulate_touch_from_mouse`).
## `value` lies in the unit disc; screen-up is negative y.

const DEAD_ZONE: float = 0.15

var radius: float = 90.0
var value: Vector2 = Vector2.ZERO
var _touch_index: int = -1
var _knob: Vector2 = Vector2.ZERO


func _ready() -> void:
	custom_minimum_size = Vector2(radius * 2.0, radius * 2.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_held() -> bool:
	return _touch_index >= 0


func owns_touch(index: int) -> bool:
	return _touch_index >= 0 and _touch_index == index


func release() -> void:
	_touch_index = -1
	value = Vector2.ZERO
	_knob = Vector2.ZERO
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		if _touch_index >= 0:
			release()
		return
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed and _touch_index < 0 and get_global_rect().has_point(touch.position):
			_touch_index = touch.index
			_track(touch.position)
		elif not touch.pressed and touch.index == _touch_index:
			release()
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if drag.index == _touch_index:
			_track(drag.position)


func _track(screen_position: Vector2) -> void:
	var offset: Vector2 = screen_position - get_global_rect().get_center()
	if offset.length() > radius:
		offset = offset.normalized() * radius
	_knob = offset
	var normalized: Vector2 = offset / radius
	value = Vector2.ZERO if normalized.length() < DEAD_ZONE else normalized
	queue_redraw()


func _draw() -> void:
	var middle: Vector2 = size * 0.5
	draw_circle(middle, radius, Color(1.0, 1.0, 1.0, 0.10))
	draw_arc(middle, radius, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.35), 2.0)
	draw_circle(middle + _knob, radius * 0.38, Color(1.0, 1.0, 1.0, 0.45 if is_held() else 0.3))
