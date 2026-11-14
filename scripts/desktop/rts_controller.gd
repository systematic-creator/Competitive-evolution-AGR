class_name RtsController
extends Node
## Desktop mouse stand-in for the AR reticle: select, move, gather, build.

var camera: Camera3D
var hud: DesktopHud
## The diorama root. Screen hits are converted into its LOCAL space before any
## order is issued, so orders are independent of the AR anchor pose / scale.
var diorama: Node3D
## Optional gate (AR placement / unlocked adjust mode) that owns touch input.
## Returns true when gameplay should NOT receive touches.
var touch_gate: Callable
## Tier 4 skirmish possession owns P / Esc while a fight is live.
var skirmish: SkirmishPossessionController
var selected_unit_id: int = -1
var _possessed_id: int = -1
## Mobile builds: a short single-finger tap selects a unit, or orders the
## selected unit to the tapped ground / resource node (no right button on touch).
var touch_enabled: bool = OS.has_feature("mobile")
const TAP_SLOP_PX: float = 24.0
var _touch_count: int = 0
var _tap_start: Vector2 = Vector2.ZERO
var _tap_valid: bool = false


func _unhandled_input(event: InputEvent) -> void:
	if camera == null or GameState.world == null:
		return
	if event is InputEventKey and event.pressed:
		var key: InputEventKey = event
		if skirmish != null and skirmish.is_active() and (key.keycode == KEY_P or key.keycode == KEY_ESCAPE):
			if key.keycode == KEY_ESCAPE:
				skirmish.request_auto_resolve()
			return
		if key.keycode == KEY_P:
			_toggle_possess()
			return
		if key.keycode == KEY_ESCAPE:
			_release()
			hud.clear_build()
			return
		if key.keycode == KEY_SPACE:
			if GameState.is_simulation_running:
				GameState.stop_simulation()
			else:
				GameState.start_simulation()
			return
	if GameState.current_zoom_tier == GameState.ZoomTier.THIRD_PERSON:
		return
	if touch_enabled:
		if touch_gate.is_valid() and bool(touch_gate.call()):
			_touch_count = 0
			_tap_valid = false
			return
		_handle_touch(event)
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	var mouse: InputEventMouseButton = event
	if mouse.button_index == MOUSE_BUTTON_LEFT:
		_primary_at(mouse.position, false)
	elif mouse.button_index == MOUSE_BUTTON_RIGHT:
		_order_at(mouse.position)


## Left click / tap: place a pending building, else select a unit. On touch,
## tapping empty ground with a unit selected issues the move/gather order.
func _primary_at(screen: Vector2, is_tap: bool) -> void:
	if GameState.current_zoom_tier < GameState.ZoomTier.RTS and hud.pending_build_type() == &"":
		return
	var hit: Dictionary = _ray(screen)
	if hit.is_empty():
		return
	var point: Vector3 = to_diorama_local(hit["position"] as Vector3)
	if hud != null and hud.pending_build_type() != &"":
		var cell: Vector2i = GameState.world.playable.world_to_cell(point)
		GameState.commands.place_building(GameState.get_player_faction_id(), hud.pending_build_type(), cell)
		hud.clear_build()
		return
	var unit: SimUnit = _unit_near(point, GameState.get_player_faction_id())
	if unit != null:
		selected_unit_id = unit.id
	elif is_tap:
		_order_at(screen)


## Right click (or a touch tap on the ground): move or gather.
func _order_at(screen: Vector2) -> void:
	if selected_unit_id < 0 or GameState.current_zoom_tier < GameState.ZoomTier.RTS:
		return
	var hit: Dictionary = _ray(screen)
	if hit.is_empty():
		return
	var point: Vector3 = to_diorama_local(hit["position"] as Vector3)
	var node: SimResourceNode = _node_near(point)
	if node != null:
		GameState.commands.assign_gather(selected_unit_id, node.node_id)
	else:
		GameState.commands.move_unit(selected_unit_id, Vector3(point.x, 0.0, point.z))


func _handle_touch(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			_touch_count += 1
			if _touch_count == 1:
				_tap_start = touch.position
				_tap_valid = true
			else:
				_tap_valid = false  # pinch, not a tap
		else:
			_touch_count = maxi(0, _touch_count - 1)
			if _tap_valid and _touch_count == 0:
				_tap_valid = false
				if hud == null or not hud.is_over_ui(touch.position):
					_primary_at(touch.position, true)
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if drag.position.distance_to(_tap_start) > TAP_SLOP_PX:
			_tap_valid = false  # orbit drag, not a tap


func _process(delta: float) -> void:
	if _possessed_id < 0 or GameState.world == null:
		return
	var unit: SimUnit = GameState.world.playable.get_unit(_possessed_id)
	if unit == null:
		return
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.z -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.z += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if dir.length() > 0.0:
		GameState.commands.move_unit(unit.id, unit.position + dir.normalized() * 0.2)


func _toggle_possess() -> void:
	if _possessed_id >= 0:
		_release()
		return
	if selected_unit_id < 0:
		return
	_possessed_id = selected_unit_id
	GameState.current_zoom_tier = GameState.ZoomTier.THIRD_PERSON
	EventBus.unit_possessed.emit(null)


func _release() -> void:
	if _possessed_id < 0:
		return
	_possessed_id = -1
	GameState.current_zoom_tier = GameState.ZoomTier.RTS
	EventBus.unit_released.emit()


## World-space hit under `screen`: physics first, then the diorama's ground
## plane (its local y = 0, wherever the anchor put it).
func _ray(screen: Vector2) -> Dictionary:
	var from: Vector3 = camera.project_ray_origin(screen)
	var direction: Vector3 = camera.project_ray_normal(screen)
	var params := PhysicsRayQueryParameters3D.create(from, from + direction * 20.0)
	var hit: Dictionary = camera.get_world_3d().direct_space_state.intersect_ray(params)
	if not hit.is_empty():
		return hit
	var ground: Plane = diorama_ground_plane()
	var point: Variant = ground.intersects_ray(from, direction)
	if point == null:
		return {}
	return {"position": point as Vector3}


func diorama_ground_plane() -> Plane:
	if diorama == null or not diorama.is_inside_tree():
		return Plane(Vector3.UP, 0.0)
	var xform: Transform3D = diorama.global_transform
	return Plane(xform.basis.y.normalized(), xform.origin)


## World -> diorama-local. Identity when there is no diorama (tests, desktop).
func to_diorama_local(world_point: Vector3) -> Vector3:
	if diorama == null or not diorama.is_inside_tree():
		return world_point
	var local: Vector3 = diorama.to_local(world_point)
	return Vector3(local.x, 0.0, local.z)


func _unit_near(point: Vector3, faction_id: StringName) -> SimUnit:
	var best: SimUnit = null
	var best_d: float = 0.04
	for unit: SimUnit in GameState.world.playable.units_for(faction_id):
		var d: float = Vector3(unit.position.x, 0, unit.position.z).distance_to(Vector3(point.x, 0, point.z))
		if d < best_d:
			best = unit
			best_d = d
	return best


func _node_near(point: Vector3) -> SimResourceNode:
	var best: SimResourceNode = null
	var best_d: float = 0.05
	for node: SimResourceNode in GameState.world.playable.nodes.values():
		if not GameState.world.can_see_node(GameState.get_player_faction_id(), node):
			continue
		var d: float = node.position.distance_to(Vector3(point.x, 0, point.z))
		if d < best_d:
			best = node
			best_d = d
	return best
