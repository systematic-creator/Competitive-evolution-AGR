class_name SimCatalog
extends Object
## Static building / unit / era costs and rules for the concept build.

const ERA_PATHS: Array[String] = [
	"res://data/eras/stone.tres",
	"res://data/eras/bronze.tres",
	"res://data/eras/iron.tres",
	"res://data/eras/industrial.tres",
]
const SPECIES_PATHS: Array[String] = [
	"res://data/species/human.tres",
	"res://data/species/sylvari.tres",
	"res://data/species/kraal.tres",
	"res://data/species/cogforged.tres",
]
const FACTION_PATHS: Array[String] = [
	"res://data/factions/humans.tres",
	"res://data/factions/sylvari.tres",
	"res://data/factions/kraal.tres",
	"res://data/factions/cogforged.tres",
]
const REGION_PATHS: Array[String] = [
	"res://data/regions/verdant_basin.tres",
	"res://data/regions/gearhold.tres",
	"res://data/regions/greenwood_expanse.tres",
	"res://data/regions/chitin_warrens.tres",
	"res://data/regions/pale_steppe.tres",
]
const NODE_LAYOUT_PATHS: Array[String] = [
	"res://data/nodes/placements/verdant_basin.tres",
]


static func load_eras() -> Array[EraData]:
	var out: Array[EraData] = []
	for path: String in ERA_PATHS:
		out.append(load(path) as EraData)
	return out


static func load_factions() -> Array[FactionData]:
	var out: Array[FactionData] = []
	for path: String in FACTION_PATHS:
		out.append(load(path) as FactionData)
	return out


static func load_regions() -> Array[RegionData]:
	var out: Array[RegionData] = []
	for path: String in REGION_PATHS:
		out.append(load(path) as RegionData)
	return out


static func load_node_layouts() -> Array[RegionNodeLayout]:
	var out: Array[RegionNodeLayout] = []
	for path: String in NODE_LAYOUT_PATHS:
		out.append(load(path) as RegionNodeLayout)
	return out


static func era_by_index(eras: Array[EraData], index: int) -> EraData:
	for era: EraData in eras:
		if era.era_index == index:
			return era
	return null


static func cost_amount(cost: Dictionary, resource_id: StringName) -> int:
	return int(cost.get(resource_id, 0))


static func building_cost(building_type: StringName) -> Dictionary:
	var cost: Dictionary = {}
	match building_type:
		SimIds.HOUSE:
			cost[SimIds.WOOD] = 40
		SimIds.FARM:
			cost[SimIds.WOOD] = 30
		SimIds.LUMBER_CAMP:
			cost[SimIds.WOOD] = 20
			cost[SimIds.STONE] = 10
		SimIds.QUARRY:
			cost[SimIds.WOOD] = 25
		SimIds.BARRACKS:
			cost[SimIds.WOOD] = 40
			cost[SimIds.STONE] = 30
		SimIds.FOUNDRY:
			cost[SimIds.WOOD] = 40
			cost[SimIds.STONE] = 25
		SimIds.EXTRACTOR:
			cost[SimIds.WOOD] = 30
			cost[SimIds.STONE] = 20
		_:
			pass
	return cost


static func building_build_ticks(building_type: StringName) -> int:
	match building_type:
		SimIds.HOUSE:
			return 3
		SimIds.FARM:
			return 3
		SimIds.LUMBER_CAMP, SimIds.QUARRY, SimIds.FOUNDRY, SimIds.EXTRACTOR:
			return 4
		SimIds.BARRACKS:
			return 5
		_:
			return 1


static func building_pop_cap(building_type: StringName) -> int:
	match building_type:
		SimIds.TOWN_CENTER:
			return 6
		SimIds.HOUSE:
			return 4
		_:
			return 0


static func building_hp(building_type: StringName) -> int:
	match building_type:
		SimIds.TOWN_CENTER:
			return 200
		SimIds.BARRACKS:
			return 140
		_:
			return 100


static func unit_base_cost(unit_type: StringName, constructed: bool = false) -> Dictionary:
	var cost: Dictionary = {}
	if constructed:
		# Cogforged constructs: industrial materials, a little fuel for soldiers.
		match unit_type:
			SimIds.WORKER:
				cost[SimIds.WOOD] = 15
				cost[SimIds.STONE] = 10
			SimIds.SOLDIER:
				cost[SimIds.WOOD] = 20
				cost[SimIds.STONE] = 15
				cost[SimIds.FOOD] = 5
			_:
				pass
		# Specialized units always add their rare costs below.
		_apply_specialized_cost(cost, unit_type)
		return cost
	match unit_type:
		SimIds.WORKER:
			cost[SimIds.FOOD] = 20
		SimIds.SOLDIER:
			cost[SimIds.FOOD] = 25
			cost[SimIds.WOOD] = 10
		_:
			pass
	_apply_specialized_cost(cost, unit_type)
	return cost


static func _apply_specialized_cost(cost: Dictionary, unit_type: StringName) -> void:
	match unit_type:
		SimIds.IRONCLAD:
			# Basic troops stay on common resources; ironclads are rare-gated.
			if not cost.has(SimIds.FOOD):
				cost[SimIds.FOOD] = 20
			if not cost.has(SimIds.WOOD):
				cost[SimIds.WOOD] = 15
			cost[SimIds.IRON] = 12
		SimIds.STEAMWALKER:
			if not cost.has(SimIds.WOOD):
				cost[SimIds.WOOD] = 20
			if not cost.has(SimIds.STONE):
				cost[SimIds.STONE] = 15
			cost[SimIds.IRON] = 10
			cost[SimIds.COAL] = 12
		_:
			pass


static func scaled_unit_cost(unit_type: StringName, species: SpeciesData) -> Dictionary:
	var constructed: bool = species != null and species.units_are_constructed
	var base: Dictionary = unit_base_cost(unit_type, constructed)
	var scaled: Dictionary = {}
	var mult: float = 1.0 if species == null else species.unit_cost_multiplier
	for resource_id: StringName in base:
		scaled[resource_id] = int(max(1.0, round(float(int(base[resource_id])) * mult)))
	return scaled


static func unit_train_ticks(unit_type: StringName, species: SpeciesData) -> int:
	var base_ticks: int = 2
	match unit_type:
		SimIds.WORKER:
			base_ticks = 2
		SimIds.SOLDIER:
			base_ticks = 3
		SimIds.IRONCLAD:
			base_ticks = 4
		SimIds.STEAMWALKER:
			base_ticks = 5
		_:
			base_ticks = 3
	var train_mult: float = 1.0 if species == null else species.train_speed_multiplier
	return maxi(1, int(ceil(float(base_ticks) / max(0.1, train_mult))))


static func unit_base_hp(unit_type: StringName) -> int:
	match unit_type:
		SimIds.WORKER:
			return 40
		SimIds.SOLDIER:
			return 70
		SimIds.IRONCLAD:
			return 110
		SimIds.STEAMWALKER:
			return 130
		_:
			return 70


static func unit_speed(unit_type: StringName, species: SpeciesData) -> float:
	var base: float = 0.14
	match unit_type:
		SimIds.WORKER:
			base = 0.14
		SimIds.SOLDIER:
			base = 0.16
		SimIds.IRONCLAD:
			base = 0.12
		SimIds.STEAMWALKER:
			base = 0.13
		_:
			base = 0.14
	var mult: float = 1.0 if species == null else species.unit_speed_multiplier
	return base * mult


static func era_advance_cost(next_index: int, species: SpeciesData) -> Dictionary:
	var cost: Dictionary = {}
	match next_index:
		1:
			# Bronze / Steamworks: commons only. Reaching this era reveals coal.
			cost[SimIds.FOOD] = 80
			cost[SimIds.WOOD] = 60
			cost[SimIds.STONE] = 40
		2:
			# Iron / Assembly: gated on coal (visible since the steam era). Reveals iron.
			cost[SimIds.FOOD] = 160
			cost[SimIds.WOOD] = 120
			cost[SimIds.STONE] = 80
			cost[SimIds.COAL] = 15
		3:
			# Industrial / Synthetics: gated on iron (visible since era 2) plus coal.
			cost[SimIds.FOOD] = 280
			cost[SimIds.WOOD] = 200
			cost[SimIds.STONE] = 150
			cost[SimIds.IRON] = 30
			cost[SimIds.COAL] = 25
		_:
			return cost
	var mult: float = 1.0 if species == null else species.era_cost_multiplier
	# Research speed also shortens the resource bar Humans need to clear.
	if species != null:
		mult /= max(0.5, species.research_speed_multiplier)
	var scaled: Dictionary = {}
	for resource_id: StringName in cost:
		scaled[resource_id] = int(max(1.0, round(float(int(cost[resource_id])) * mult)))
	return scaled


static func era_advance_min_pop(next_index: int) -> int:
	match next_index:
		1:
			return 4
		2:
			return 7
		3:
			return 10
		_:
			return 99


static func trainer_for(unit_type: StringName, species: SpeciesData = null) -> StringName:
	if unit_type == SimIds.WORKER:
		return SimIds.TOWN_CENTER
	# Cogforged soldiers and steamwalkers are assembled at a Foundry.
	if species != null and species.units_are_constructed:
		return SimIds.FOUNDRY
	return SimIds.BARRACKS


static func uses_only_common_resources(unit_type: StringName) -> bool:
	return not SimIds.is_specialized_unit(unit_type)
