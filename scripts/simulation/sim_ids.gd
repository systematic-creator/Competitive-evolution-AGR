class_name SimIds
extends Object
## Shared StringName identifiers for resources, buildings, units, and tiles.

const FOOD: StringName = &"food"
const WOOD: StringName = &"wood"
const STONE: StringName = &"stone"
const IRON: StringName = &"iron"
const COAL: StringName = &"coal"

const TOWN_CENTER: StringName = &"town_center"
const HOUSE: StringName = &"house"
const FARM: StringName = &"farm"
const LUMBER_CAMP: StringName = &"lumber_camp"
const QUARRY: StringName = &"quarry"
const BARRACKS: StringName = &"barracks"
const FOUNDRY: StringName = &"foundry"
const EXTRACTOR: StringName = &"extractor"
const OUTPOST: StringName = &"outpost"

const WORKER: StringName = &"worker"
const SOLDIER: StringName = &"soldier"
## Specialized unit: requires iron. Basic worker/soldier use only common resources.
const IRONCLAD: StringName = &"ironclad"
## Specialized unit: requires iron and coal. Unlocked conceptually with later eras.
const STEAMWALKER: StringName = &"steamwalker"

const TILE_LAND: int = 0
const TILE_WATER: int = 1
const TILE_COAST: int = 2

const PLAYABLE_REGION: StringName = &"verdant_basin"
const PLAYER_FACTION: StringName = &"humans"


static func all_resources() -> Array[StringName]:
	var ids: Array[StringName] = [FOOD, WOOD, STONE, IRON, COAL]
	return ids


static func common_resources() -> Array[StringName]:
	var ids: Array[StringName] = [FOOD, WOOD, STONE]
	return ids


static func rare_resources() -> Array[StringName]:
	var ids: Array[StringName] = [IRON, COAL]
	return ids


static func is_rare_resource(resource_id: StringName) -> bool:
	return resource_id == IRON or resource_id == COAL


static func all_building_types() -> Array[StringName]:
	var ids: Array[StringName] = [
		TOWN_CENTER, HOUSE, FARM, LUMBER_CAMP, QUARRY, BARRACKS, FOUNDRY, EXTRACTOR, OUTPOST
	]
	return ids


static func all_unit_types() -> Array[StringName]:
	var ids: Array[StringName] = [WORKER, SOLDIER, IRONCLAD, STEAMWALKER]
	return ids


static func is_specialized_unit(unit_type: StringName) -> bool:
	return unit_type == IRONCLAD or unit_type == STEAMWALKER
