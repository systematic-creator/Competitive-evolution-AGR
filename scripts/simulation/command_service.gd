class_name CommandService
extends RefCounted
## The only way UI and tests issue orders into SimWorld.

var world: SimWorld


func place_building(faction_id: StringName, building_type: StringName, cell: Vector2i) -> int:
	if world == null:
		return -1
	return world.place_building(faction_id, building_type, cell)


func train_unit(faction_id: StringName, unit_type: StringName) -> bool:
	if world == null:
		return false
	return world.queue_training(faction_id, unit_type)


func move_unit(unit_id: int, destination: Vector3) -> bool:
	if world == null:
		return false
	return world.order_move(unit_id, destination)


func assign_gather(unit_id: int, node_id: StringName) -> bool:
	if world == null:
		return false
	return world.order_gather(unit_id, node_id)


func advance_era(faction_id: StringName) -> bool:
	if world == null:
		return false
	return world.try_advance_era(faction_id)
