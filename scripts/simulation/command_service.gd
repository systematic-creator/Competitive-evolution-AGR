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


## Tier 4: take control of one attacking squad member and start the live fight.
func possess_skirmish_unit(skirmish_id: int, unit_id: int) -> bool:
	return bool(submit({
		"type": &"possess_skirmish_unit",
		"skirmish_id": skirmish_id,
		"unit_id": unit_id,
	}))


## Tier 4: steer the possessed unit. `sector` is 0..SkirmishCombat.STEER_SECTORS-1
## (0 = -Z, clockwise) or -1 to stop. Send only when the sector changes.
func steer_possessed(skirmish_id: int, sector: int) -> bool:
	return bool(submit({
		"type": &"steer_possessed",
		"skirmish_id": skirmish_id,
		"sector": sector,
	}))


## Tier 4: queue a strike for the possessed unit.
func possessed_attack(skirmish_id: int) -> bool:
	return bool(submit({
		"type": &"possessed_attack",
		"skirmish_id": skirmish_id,
	}))


## Tier 4: settle a possession fight once `skirmish_combat_finished` fired.
func resolve_skirmish_possessed(skirmish_id: int) -> bool:
	return bool(submit({
		"type": &"resolve_skirmish_possessed",
		"skirmish_id": skirmish_id,
	}))


func submit(command: Dictionary) -> Variant:
	if world == null:
		return _empty_result(command)
	var stamped: Dictionary = command.duplicate()
	if not stamped.has("tick"):
		stamped["tick"] = world.current_tick
	if not stamped.has("combat_step"):
		stamped["combat_step"] = world.combat_step
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
		&"possess_skirmish_unit":
			return world.possess_skirmish_unit(int(command.get("skirmish_id", -1)), int(command.get("unit_id", -1)))
		&"steer_possessed":
			return world.steer_possessed(int(command.get("skirmish_id", -1)), int(command.get("sector", -1)))
		&"possessed_attack":
			return world.possessed_attack(int(command.get("skirmish_id", -1)))
		&"resolve_skirmish_possessed":
			return world.resolve_skirmish_possessed(int(command.get("skirmish_id", -1)))
		_:
			return _empty_result(command)


## Replay a command log against the current world. Steps with AI disabled
## until each command's (tick, combat_step) stamp, applies the command without
## re-recording, then steps to `final_tick` / `final_combat_step`.
## Pass `world.combat_step` from the original run as `final_combat_step` when
## the log ends inside a live possession fight.
func replay(log: Array, final_tick: int, final_combat_step: int = -1) -> void:
	if world == null:
		return
	var previous: bool = recording
	recording = false
	# Callers should have already turned AI off; keep it off here.
	for item: Variant in log:
		var command: Dictionary = item as Dictionary
		_step_until(int(command.get("tick", 0)), int(command.get("combat_step", 0)))
		apply(command)
	_step_until(final_tick, final_combat_step)
	recording = previous


## Strategic ticks are held while a possession fight is live, so combat steps
## always sit between two ticks: advance ticks first, then combat steps.
func _step_until(tick: int, combat_step: int = -1) -> void:
	while world.current_tick < tick:
		if GameState != null:
			GameState.step_ticks(1)
		else:
			world.step(world.current_tick + 1, false)
			world.current_tick += 1
	while world.combat_step < combat_step:
		world.step_combat()


func _empty_result(command: Dictionary) -> Variant:
	var kind: StringName = command.get("type", &"") as StringName
	if kind == &"place_building" or kind == &"start_skirmish":
		return -1
	return false
