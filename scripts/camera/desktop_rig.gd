class_name DesktopRig
extends Node3D
## Mouse-wheel distance stand-in for the AR camera, plus orbit drag.

@export var min_distance: float = 0.20
@export var max_distance: float = 2.4
@export var distance: float = 1.7
@export var zoom_step: float = 0.08
@export var yaw: float = 0.55
@export var pitch: float = 0.7
@export var auto_zoom_speed: float = 1.6

var camera: Camera3D
var _target_distance: float = 1.7
var auto_zoom_to: float = -1.0
var third_person: bool = false
var frozen: bool = false
## In AR the phone's real pose is the camera: this rig neither renders,
## takes input, nor drives the zoom tier.
var ar_mode: bool = false
## Touch stand-in for the scroll wheel / middle drag (mobile builds only):
## pinch = distance, one-finger drag = orbit.
var touch_enabled: bool = OS.has_feature("mobile")
var _touches: Dictionary = {}
var _pinch_last: float = -1.0


func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "DesktopCamera"
	camera.fov = 50.0
	camera.near = 0.05
	camera.far = 20.0
	add_child(camera)
	_target_distance = distance
	_apply_transform()


func _unhandled_input(event: InputEvent) -> void:
	if ar_mode:
		return
	if third_person:
		_touches.clear()
		_pinch_last = -1.0
		return
	if touch_enabled and (event is InputEventScreenTouch or event is InputEventScreenDrag):
		_handle_touch(event)
		return
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event
		if mouse.button_index == MOUSE_BUTTON_WHEEL_UP and mouse.pressed:
			_target_distance = maxf(min_distance, _target_distance - zoom_step)
			auto_zoom_to = -1.0
		elif mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse.pressed:
			_target_distance = minf(max_distance, _target_distance + zoom_step)
			auto_zoom_to = -1.0
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		var motion: InputEventMouseMotion = event
		yaw -= motion.relative.x * 0.005
		pitch = clampf(pitch + motion.relative.y * 0.005, 0.15, 1.35)


func _process(delta: float) -> void:
	if ar_mode:
		return
	if third_person or frozen:
		_apply_transform()
		return
	if auto_zoom_to >= 0.0:
		_target_distance = move_toward(_target_distance, auto_zoom_to, auto_zoom_speed * delta)
		if is_equal_approx(_target_distance, auto_zoom_to):
			auto_zoom_to = -1.0
	distance = lerpf(distance, _target_distance, clampf(delta * 10.0, 0.0, 1.0))
	_apply_transform()
	if GameState.current_zoom_tier != GameState.ZoomTier.THIRD_PERSON:
		GameState.current_zoom_tier = ZoomTierController.tier_for_distance(distance)
	EventBus.zoom_transition_progress.emit(ZoomTierController.transition_progress(distance))


func request_distance(value: float) -> void:
	auto_zoom_to = clampf(value, min_distance, max_distance)


func _apply_transform() -> void:
	var offset := Vector3(
		sin(yaw) * cos(pitch),
		sin(pitch),
		cos(yaw) * cos(pitch)
	) * distance
	camera.position = offset
	camera.look_at(global_position, Vector3.UP)


func _handle_touch(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			_touches[touch.index] = touch.position
		else:
			_touches.erase(touch.index)
		_pinch_last = _pinch_span()
		return
	var drag: InputEventScreenDrag = event
	_touches[drag.index] = drag.position
	if _touches.size() >= 2:
		var span: float = _pinch_span()
		if _pinch_last > 1.0 and span > 1.0:
			# Fingers apart = move closer (like scrolling in).
			_target_distance = clampf(_target_distance * (_pinch_last / span), min_distance, max_distance)
			auto_zoom_to = -1.0
		_pinch_last = span
	elif _touches.size() == 1:
		yaw -= drag.relative.x * 0.006
		pitch = clampf(pitch + drag.relative.y * 0.006, 0.15, 1.35)


func _pinch_span() -> float:
	if _touches.size() < 2:
		return -1.0
	var points: Array = _touches.values()
	return (points[0] as Vector2).distance_to(points[1] as Vector2)
