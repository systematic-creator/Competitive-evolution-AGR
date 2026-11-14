class_name ARGestureTracker
extends RefCounted
## Turns raw touch events into tap / drag / pinch+twist gestures.
## Pure input math, no scene access, so it is unit-tested headless.
##
## handle() returns {} or one of:
##   {"kind": &"tap", "position": Vector2}
##   {"kind": &"drag", "from": Vector2, "to": Vector2}
##   {"kind": &"pinch", "scale": float, "twist": float}  (twist: radians,
##   positive = clockwise on screen)

const TAP_SLOP_PX: float = 24.0

var _touches: Dictionary = {}
var _tap_start: Vector2 = Vector2.ZERO
var _tap_possible: bool = false


func reset() -> void:
	_touches.clear()
	_tap_possible = false


func touch_count() -> int:
	return _touches.size()


func handle(event: InputEvent) -> Dictionary:
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			_touches[touch.index] = touch.position
			if _touches.size() == 1:
				_tap_start = touch.position
				_tap_possible = true
			else:
				_tap_possible = false
			return {}
		var was_single: bool = _touches.size() == 1
		_touches.erase(touch.index)
		if was_single and _tap_possible:
			_tap_possible = false
			return {"kind": &"tap", "position": touch.position}
		return {}
	if event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		var previous: Vector2 = _touches.get(drag.index, drag.position - drag.relative) as Vector2
		_touches[drag.index] = drag.position
		if drag.position.distance_to(_tap_start) > TAP_SLOP_PX:
			_tap_possible = false
		if _touches.size() == 1:
			return {"kind": &"drag", "from": previous, "to": drag.position}
		if _touches.size() >= 2:
			var other: Vector2 = _other_touch(drag.index)
			var before: Vector2 = previous - other
			var after: Vector2 = drag.position - other
			if before.length() < 1.0 or after.length() < 1.0:
				return {}
			return {
				"kind": &"pinch",
				"scale": after.length() / before.length(),
				"twist": before.angle_to(after),
			}
	return {}


func _other_touch(index: int) -> Vector2:
	var keys: Array = _touches.keys()
	keys.sort()
	for key: Variant in keys:
		if int(key) != index:
			return _touches[key] as Vector2
	return Vector2.ZERO
