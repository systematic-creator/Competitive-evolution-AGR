class_name RtsController
extends Node
## Desktop mouse stand-in for the AR reticle: select, move, gather, build.

var camera: Camera3D
var hud: DesktopHud
## Tier 4 skirmish possession owns P / Esc while a fight is live.
var skirmish: SkirmishPossessionController
var selected_unit_id: int = -1
var _possessed_id: int = -1


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
	if not (event is InputEventMouseButton and event.pressed):
		return
	if GameState.current_zoom_tier < GameState.ZoomTier.RTS and hud.pending_build_type() == &"":
		return
	var mouse: InputEventMouseButton = event
	var hit: Dictionary = _ray(mouse.position)
	if hit.is_empty():
		return
	var point: Vector3 = hit["position"] as Vector3
	if mouse.button_index == MOUSE_BUTTON_LEFT:
		if hud != null and hud.pending_build_type() != &"":
			var cell: Vector2i = GameState.world.playable.world_to_cell(point)
			GameState.commands.place_building(GameState.get_player_faction_id(), hud.pending_build_type(), cell)
			hud.clear_build()
			return
		var unit: SimUnit = _unit_near(point, GameState.get_player_faction_id())
		if unit != null:
			selected_unit_id = unit.id
	elif mouse.button_index == MOUSE_BUTTON_RIGHT and selected_unit_id >= 0:
		var node: SimResourceNode = _node_near(point)
		if node != null:
			GameState.commands.assign_gather(selected_unit_id, node.node_id)
		else:
			GameState.commands.move_unit(selected_unit_id, Vector3(point.x, 0.0, point.z))


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


func _ray(screen: Vector2) -> Dictionary:
	var from: Vector3 = camera.project_ray_origin(screen)
	var to: Vector3 = from + camera.project_ray_normal(screen) * 20.0
	var params := PhysicsRayQueryParameters3D.create(from, to)
	var hit: Dictionary = camera.get_world_3d().direct_space_state.intersect_ray(params)
	if not hit.is_empty():
		return hit
	# Plane fallback at y=0 so we can click the diorama without colliders.
	var n: Vector3 = camera.project_ray_normal(screen)
	if abs(n.y) < 0.0001:
		return {}
	var t: float = -from.y / n.y
	if t <= 0.0:
		return {}
	return {"position": from + n * t}


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
