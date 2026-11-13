class_name CommandService
extends RefCounted
## The only way UI, AI, and tests issue orders into SimWorld.
## Every mutation is a serializable dictionary stamped with the current tick
## and appended to `world.command_log` for replay.

var world: SimWorld
var recording: bool = true


func place_building(faction_id: StringName, building_type: StringName, cell: Vector2i) -> int:
	var result: Variant = submit({
		"type": &"place_building",
		"faction_id": faction_id,
		"building_type": building_type,
		"cell_x": cell.x,
		"cell_y": cell.y,
	})
	return int(result)


func train_unit(faction_id: StringName, unit_type: StringName) -> bool:
	return bool(submit({
		"type": &"train_unit",
		"faction_id": faction_id,
		"unit_type": unit_type,
	}))


func move_unit(unit_id: int, destination: Vector3) -> bool:
	return bool(submit({
		"type": &"move_unit",
		"unit_id": unit_id,
		"x": destination.x,
		"y": destination.y,
		"z": destination.z,
	}))


func assign_gather(unit_id: int, node_id: StringName) -> bool:
	return bool(submit({
		"type": &"assign_gather",
		"unit_id": unit_id,
		"node_id": node_id,
	}))


func advance_era(faction_id: StringName) -> bool:
	return bool(submit({
		"type": &"advance_era",
		"faction_id": faction_id,
	}))


func start_skirmish(faction_id: StringName, node_id: StringName, hex: Vector2i, auto_battle: bool = true) -> int:
	return int(submit({
		"type": &"start_skirmish",
		"faction_id": faction_id,
		"node_id": node_id,
		"hex_key": HexGrid.pack(hex),
		"auto_battle": auto_battle,
	}))


func resolve_skirmish_auto(skirmish_id: int) -> bool:
	return bool(submit({
		"type": &"resolve_skirmish",
		"skirmish_id": skirmish_id,
	}))


func submit(command: Dictionary) -> Variant:
	if world == null:
		return _empty_result(command)
	var stamped: Dictionary = command.duplicate()
	if not stamped.has("tick"):
		stamped["tick"] = world.current_tick
	if recording:
		world.command_log.append(stamped)
	return apply(stamped)


func apply(command: Dictionary) -> Variant:
	if world == null:
		return _empty_result(command)
	var kind: StringName = command.get("type", &"") as StringName
	match kind:
		&"place_building":
			return world.place_building(
				command.get("faction_id", &"") as StringName,
				command.get("building_type", &"") as StringName,
				Vector2i(int(command.get("cell_x", 0)), int(command.get("cell_y", 0)))
			)
		&"train_unit":
			return world.queue_training(
				command.get("faction_id", &"") as StringName,
				command.get("unit_type", &"") as StringName
			)
		&"move_unit":
			return world.order_move(
				int(command.get("unit_id", -1)),
				Vector3(float(command.get("x", 0.0)), float(command.get("y", 0.0)), float(command.get("z", 0.0)))
			)
		&"assign_gather":
			return world.order_gather(
				int(command.get("unit_id", -1)),
				command.get("node_id", &"") as StringName
			)
		&"advance_era":
			return world.try_advance_era(command.get("faction_id", &"") as StringName)
		&"start_skirmish":
			return world.start_skirmish(
				command.get("faction_id", &"") as StringName,
				command.get("node_id", &"") as StringName,
				HexGrid.unpack(int(command.get("hex_key", 0))),
				bool(command.get("auto_battle", true))
			)
		&"resolve_skirmish":
			return world.resolve_skirmish_auto(int(command.get("skirmish_id", -1)))
		_:
			return _empty_result(command)


## Replay a command log against the current world. Steps with AI disabled
## until each command's tick, applies the command without re-recording,
## then steps to `final_tick`.
func replay(log: Array, final_tick: int) -> void:
	if world == null:
		return
	var previous: bool = recording
	recording = false
	var previous_ai: bool = true
	# Callers should have already turned AI off; keep it off here.
	for item: Variant in log:
		var command: Dictionary = item as Dictionary
		var at: int = int(command.get("tick", 0))
		_step_until(at)
		apply(command)
	_step_until(final_tick)
	recording = previous


func _step_until(tick: int) -> void:
	while world.current_tick < tick:
		if GameState != null:
			GameState.step_ticks(1)
		else:
			world.step(world.current_tick + 1, false)
			world.current_tick += 1


func _empty_result(command: Dictionary) -> Variant:
	var kind: StringName = command.get("type", &"") as StringName
	if kind == &"place_building" or kind == &"start_skirmish":
		return -1
	return false
