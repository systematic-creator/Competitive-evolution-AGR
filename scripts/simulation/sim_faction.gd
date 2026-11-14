class_name SimFaction
extends RefCounted
## Runtime state for one faction: stockpiles, era, and census.

var data: FactionData
var species: SpeciesData
var era: EraData
var resources: Dictionary = {}
var pending_trains: Array[Dictionary] = []


func faction_id() -> StringName:
	return data.faction_id


func is_player() -> bool:
	return data.is_player


func get_resource(resource_id: StringName) -> int:
	return int(resources.get(resource_id, 0))


func set_resource(resource_id: StringName, amount: int) -> void:
	resources[resource_id] = maxi(0, amount)
	EventBus.faction_resource_changed.emit(faction_id(), resource_id, get_resource(resource_id))


func add_resource(resource_id: StringName, delta: int) -> void:
	if delta == 0:
		return
	set_resource(resource_id, get_resource(resource_id) + delta)


func can_afford(cost: Dictionary) -> bool:
	for resource_id: StringName in cost:
		if get_resource(resource_id) < int(cost[resource_id]):
			return false
	return true


func pay(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for resource_id: StringName in cost:
		add_resource(resource_id, -int(cost[resource_id]))
	return true
