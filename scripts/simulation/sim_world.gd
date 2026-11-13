class_name SimWorld
extends RefCounted
## Authoritative concept simulation: factions, the playable region, and tick step.

var eras: Array[EraData] = []
var region_catalog: Array[RegionData] = []
var factions: Dictionary = {}
var playable: SimRegion
var player_faction_id: StringName = SimIds.PLAYER_FACTION
var ticks: ResourceTick = ResourceTick.new()
var upgrades: BuildingUpgradeSystem = BuildingUpgradeSystem.new()
var ai: FactionAI = FactionAI.new()
var claims: ClaimSystem = ClaimSystem.new()
var victory: VictorySystem = VictorySystem.new()
var node_layouts: Array[RegionNodeLayout] = []
## species_id -> Array[EraData]
var species_eras: Dictionary = {}
var world_era_index: int = 0
var world_era_elapsed: int = 0
var current_tick: int = 0
## Fixed combat steps taken by live Tier 4 skirmishes. The strategic tick is
## held while a fight is live, so (current_tick, combat_step) orders every event.
var combat_step: int = 0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var rng_seed: int = 1
var command_log: Array[Dictionary] = []
## Set by GameState after bootstrap so AI orders go through CommandService.
var commands: CommandService

## Starting town centers: SW Humans, NW Sylvari, NE Kraal, SE Cogforged.
const START_CELLS: Dictionary = {
	&"humans": Vector2i(1, 14),
	&"sylvari": Vector2i(1, 1),
	&"kraal": Vector2i(14, 1),
	&"cogforged": Vector2i(14, 14),
}


func bootstrap_default(p_seed: int = 1) -> void:
	configure_seed(p_seed)
	current_tick = 0
	combat_step = 0
	command_log.clear()
	world_era_index = 0
	world_era_elapsed = 0
	eras = SimCatalog.load_world_eras()
	PrimitiveCatalog.apply_to_eras(eras)
	species_eras.clear()
	for species_id: StringName in SimCatalog.SPECIES_ERA_PATHS:
		var track: Array[EraData] = SimCatalog.load_eras_for_species(species_id)
		PrimitiveCatalog.apply_to_eras(track)
		species_eras[species_id] = track
	victory.setup(SimCatalog.load_win_conditions())
	region_catalog = SimCatalog.load_regions()
	node_layouts = SimCatalog.load_node_layouts()
	_bootstrap_factions()
	_bootstrap_playable()
	_place_starting_pieces()
	_place_nodes()
	claims.update(self)
	victory.evaluate(self)


func _bootstrap_factions() -> void:
	factions.clear()
	for data: FactionData in SimCatalog.load_factions():
		var sim := SimFaction.new()
		sim.data = data
		sim.species = data.species
		var start_index: int = 0 if data.species == null else data.species.starting_era_index
		sim.era = SimCatalog.era_by_index(eras_for_faction(sim), start_index)
		if sim.era == null and not eras.is_empty():
			sim.era = eras[0]
		for resource_id: StringName in SimIds.all_resources():
			var starting: int = 0
			if data.species != null:
				starting = data.species.get_starting_resource(resource_id)
			sim.resources[resource_id] = starting
		factions[data.faction_id] = sim
		if data.is_player:
			player_faction_id = data.faction_id


func _bootstrap_playable() -> void:
	playable = SimRegion.new()
	for data: RegionData in region_catalog:
		if data.region_id == SimIds.PLAYABLE_REGION:
			playable.data = data
			break
	if playable.data == null:
		push_error("SimWorld: playable region %s not found" % SimIds.PLAYABLE_REGION)
		return
	playable.setup_tiles()


func _place_starting_pieces() -> void:
	for faction_id: StringName in factions:
		var cell: Vector2i = START_CELLS.get(faction_id, Vector2i(8, 8)) as Vector2i
		if playable.is_water(cell):
			cell = _first_land_near(cell)
		var building: SimBuilding = _make_building(faction_id, SimIds.TOWN_CENTER, cell, true)
		playable.add_building(building)
		EventBus.building_placed.emit(faction_id, building.id, building.building_type, cell)
		EventBus.building_constructed.emit(faction_id, building.id, building.building_type, cell)
		var species: SpeciesData = get_faction(faction_id).species
		var count: int = 3 if species == null else species.starting_unit_count
		var offsets: Array[Vector2i] = [
			Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
		]
		var spawned: int = 0
		for offset: Vector2i in offsets:
			if spawned >= count:
				break
			var spawn_cell: Vector2i = cell + offset
			if not playable.is_cell_in_bounds(spawn_cell) or playable.is_water(spawn_cell):
				continue
			_spawn_unit(faction_id, SimIds.WORKER, playable.cell_to_world(spawn_cell))
			spawned += 1
		while spawned < count:
			_spawn_unit(faction_id, SimIds.WORKER, playable.cell_to_world(cell) + Vector3(0.04 * float(spawned), 0.0, 0.0))
			spawned += 1


func _place_nodes() -> void:
	var layout: RegionNodeLayout = null
	for candidate: RegionNodeLayout in node_layouts:
		if candidate != null and candidate.region_id == playable.region_id():
			layout = candidate
			break
	if layout == null:
		push_error("SimWorld: no node layout for %s" % playable.region_id())
		return
	var index: int = 1
	for placement: ResourceNodePlacement in layout.placements:
		if placement == null or placement.node_type == null:
			continue
		var node := SimResourceNode.new()
		var type_id: StringName = placement.node_type.node_type_id
		node.node_id = StringName("%s_%d" % [String(type_id), index])
		index += 1
		node.data = placement.node_type
		node.cell = placement.cell
		node.position = playable.cell_to_world(placement.cell)
		node.hex = playable.hex_at_world(node.position)
		node.capacity = placement.node_type.capacity
		node.remaining = placement.node_type.capacity
		playable.add_node(node)


func _first_land_near(cell: Vector2i) -> Vector2i:
	for radius: int in range(0, 6):
		for dx: int in range(-radius, radius + 1):
			for dy: int in range(-radius, radius + 1):
				var c: Vector2i = cell + Vector2i(dx, dy)
				if playable.is_cell_in_bounds(c) and not playable.is_water(c):
					return c
	return cell


func _make_building(faction_id: StringName, building_type: StringName, cell: Vector2i, complete: bool) -> SimBuilding:
	var building := SimBuilding.new()
	building.id = playable.alloc_id()
	building.faction_id = faction_id
	building.building_type = building_type
	building.grid_pos = cell
	building.max_hp = SimCatalog.building_hp(building_type)
	building.hp = building.max_hp
	building.build_ticks_required = SimCatalog.building_build_ticks(building_type)
	building.constructed = complete
	building.build_progress = float(building.build_ticks_required) if complete else 0.0
	return building


func _spawn_unit(faction_id: StringName, unit_type: StringName, position: Vector3) -> SimUnit:
	var faction: SimFaction = get_faction(faction_id)
	var species: SpeciesData = null if faction == null else faction.species
	var unit := SimUnit.new()
	unit.id = playable.alloc_id()
	unit.faction_id = faction_id
	unit.unit_type = unit_type
	unit.position = position
	unit.max_hp = SimCatalog.unit_base_hp(unit_type)
	if species != null:
		unit.max_hp = int(round(float(unit.max_hp) * species.unit_health_multiplier))
	unit.hp = unit.max_hp
	unit.speed = SimCatalog.unit_speed(unit_type, species)
	playable.add_unit(unit)
	EventBus.unit_spawned.emit(faction_id, unit.id, unit_type, position)
	return unit


func faction_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for faction_id: StringName in factions:
		ids.append(faction_id)
	return ids


func get_faction(faction_id: StringName) -> SimFaction:
	return factions.get(faction_id) as SimFaction


func get_region_data(region_id: StringName) -> RegionData:
	for data: RegionData in region_catalog:
		if data.region_id == region_id:
			return data
	return null


func step(tick: int, ai_enabled: bool = true) -> void:
	# Invariant: the strategic clock never advances past a live possession
	# fight. Live play holds ticks while one runs; if a caller steps anyway
	# (tests, replays), the fight is fought out first so ordering stays exact.
	while has_live_combat():
		step_combat()
	current_tick = tick
	upgrades.progress_construction(self)
	claims.update(self)
	upgrades.progress_training(self)
	ticks.apply(self)
	_move_units()
	claims.refresh_occupation(playable)
	_advance_world_era()
	if ai_enabled:
		for faction_id: StringName in faction_ids():
			var faction: SimFaction = get_faction(faction_id)
			if faction != null and not faction.is_player():
				ai.act(self, faction, tick)
	victory.evaluate(self)


func _move_units() -> void:
	if playable == null:
		return
	for unit: SimUnit in playable.units.values():
		if unit.view_attached or unit.in_combat or not unit.has_destination:
			continue
		var delta: Vector3 = unit.destination - unit.position
		delta.y = 0.0
		var distance: float = delta.length()
		var step_len: float = unit.speed
		if distance <= step_len or distance <= 0.0001:
			unit.position = unit.destination
			if unit.assigned_node_id == &"":
				unit.has_destination = false
			continue
		unit.position += delta * (step_len / distance)


func place_building(faction_id: StringName, building_type: StringName, cell: Vector2i) -> int:
	var faction: SimFaction = get_faction(faction_id)
	if faction == null or playable == null:
		return -1
	if building_type == SimIds.EXTRACTOR:
		if faction.species == null or not faction.species.can_build_extractors:
			return -1
		if not _cell_adjacent_to_visible_rare(faction_id, cell):
			return -1
	if building_type == SimIds.OUTPOST:
		if not claims.is_near_visible_rare(self, faction_id, cell):
			return -1
	if not playable.can_place(cell, building_type, false):
		return -1
	var cost: Dictionary = SimCatalog.building_cost(building_type)
	if not faction.pay(cost):
		return -1
	var building: SimBuilding = _make_building(faction_id, building_type, cell, false)
	playable.add_building(building)
	EventBus.building_placed.emit(faction_id, building.id, building.building_type, cell)
	return building.id


func queue_training(faction_id: StringName, unit_type: StringName) -> bool:
	var faction: SimFaction = get_faction(faction_id)
	if faction == null or playable == null:
		return false
	var trainer: StringName = SimCatalog.trainer_for(unit_type, faction.species)
	var trainer_id: int = -1
	for building: SimBuilding in playable.buildings_for(faction_id):
		if building.constructed and (
			building.building_type == trainer
			or (unit_type != SimIds.WORKER and building.building_type == SimIds.BARRACKS)
		):
			trainer_id = building.id
			break
	if trainer_id < 0:
		return false
	if playable.population(faction_id) + _pending_train_count(faction) >= playable.population_cap(faction_id):
		return false
	var cost: Dictionary = SimCatalog.scaled_unit_cost(unit_type, faction.species)
	for resource_id: StringName in cost:
		if SimIds.is_rare_resource(resource_id) and not can_see_resource(faction_id, resource_id):
			return false
	if not faction.pay(cost):
		return false
	var job: Dictionary = {
		"unit_type": unit_type,
		"ticks": SimCatalog.unit_train_ticks(unit_type, faction.species),
		"building_id": trainer_id,
	}
	faction.pending_trains.append(job)
	return true


func _pending_train_count(faction: SimFaction) -> int:
	return faction.pending_trains.size()


func spawn_trained_unit(faction_id: StringName, unit_type: StringName, at_building_id: int) -> void:
	var building: SimBuilding = playable.get_building(at_building_id)
	var origin: Vector3 = Vector3.ZERO
	if building != null:
		origin = playable.cell_to_world(building.grid_pos) + Vector3(playable.cell_size(), 0.0, 0.0)
	_spawn_unit(faction_id, unit_type, origin)


func order_move(unit_id: int, destination: Vector3) -> bool:
	if playable == null:
		return false
	var unit: SimUnit = playable.get_unit(unit_id)
	if unit == null:
		return false
	unit.assigned_node_id = &""
	unit.set_destination(destination)
	EventBus.unit_destination_set.emit(unit_id, destination)
	return true


func order_gather(unit_id: int, node_id: StringName) -> bool:
	if playable == null:
		return false
	var unit: SimUnit = playable.get_unit(unit_id)
	var node: SimResourceNode = playable.get_node(node_id)
	if unit == null or node == null or unit.unit_type != SimIds.WORKER:
		return false
	if not can_see_node(unit.faction_id, node):
		return false
	unit.assigned_node_id = node_id
	unit.set_destination(node.position)
	EventBus.unit_destination_set.emit(unit_id, node.position)
	return true


func try_advance_era(faction_id: StringName) -> bool:
	return upgrades.advance_era(self, get_faction(faction_id))


func can_see_node(faction_id: StringName, node: SimResourceNode) -> bool:
	if node == null:
		return false
	var required: int = node.reveal_era()
	if required <= 0:
		return true
	var faction: SimFaction = get_faction(faction_id)
	if faction == null or faction.era == null:
		return false
	return faction.era.era_index >= required


func can_see_resource(faction_id: StringName, resource_id: StringName) -> bool:
	if not SimIds.is_rare_resource(resource_id):
		return true
	var required: int = reveal_era_for_resource(resource_id)
	var faction: SimFaction = get_faction(faction_id)
	if faction == null or faction.era == null:
		return required <= 0
	return faction.era.era_index >= required


func reveal_era_for_resource(resource_id: StringName) -> int:
	if playable != null:
		for node: SimResourceNode in playable.nodes.values():
			if node.resource_id() == resource_id:
				return node.reveal_era()
	if resource_id == SimIds.IRON:
		return 2
	if resource_id == SimIds.COAL:
		return 1
	return 0


func set_faction_era(faction_id: StringName, era_index: int) -> bool:
	var faction: SimFaction = get_faction(faction_id)
	var next_era: EraData = SimCatalog.era_by_index(eras_for_faction(faction), era_index)
	if faction == null or next_era == null:
		return false
	var previous: EraData = faction.era
	if previous != null and previous.era_index == era_index:
		return true
	faction.era = next_era
	EventBus.era_changed.emit(faction_id, next_era, previous)
	return true


func extractor_bonus_for(region: SimRegion, node: SimResourceNode, faction_id: StringName) -> float:
	if node == null or not node.is_rare() or not can_see_node(faction_id, node):
		return 0.0
	var faction: SimFaction = get_faction(faction_id)
	if faction == null or faction.species == null or not faction.species.can_build_extractors:
		return 0.0
	for building: SimBuilding in region.buildings_for(faction_id):
		if not building.constructed or building.building_type != SimIds.EXTRACTOR:
			continue
		var dx: int = abs(building.grid_pos.x - node.cell.x)
		var dy: int = abs(building.grid_pos.y - node.cell.y)
		if maxi(dx, dy) == 1:
			return faction.species.extractor_rare_yield_bonus
	return 0.0


func _cell_adjacent_to_visible_rare(faction_id: StringName, cell: Vector2i) -> bool:
	for node: SimResourceNode in playable.nodes.values():
		if not node.is_rare() or not can_see_node(faction_id, node):
			continue
		if maxi(abs(cell.x - node.cell.x), abs(cell.y - node.cell.y)) == 1:
			return true
	return false


func start_skirmish(faction_id: StringName, node_id: StringName, hex: Vector2i, auto_battle: bool = true) -> int:
	return claims.start_skirmish(self, faction_id, node_id, hex, auto_battle)


func resolve_skirmish_auto(skirmish_id: int) -> bool:
	return claims.resolve_auto_battle(self, skirmish_id)


## Tier 4: hand `unit_id` (an attacking squad member) to the player and start
## the live fight for a pending possession skirmish.
func possess_skirmish_unit(skirmish_id: int, unit_id: int) -> bool:
	return claims.possess_unit(self, skirmish_id, unit_id)


## Tier 4: steer the possessed unit along a quantized sector (-1 = stop).
func steer_possessed(skirmish_id: int, sector: int) -> bool:
	return claims.steer_possessed(skirmish_id, sector)


## Tier 4: queue a strike for the possessed unit on the next ready combat step.
func possessed_attack(skirmish_id: int) -> bool:
	return claims.queue_possessed_attack(skirmish_id)


## Tier 4: settle a finished possession fight (captures, claims, signals).
func resolve_skirmish_possessed(skirmish_id: int) -> bool:
	return claims.resolve_possessed(self, skirmish_id)


func has_live_combat() -> bool:
	return claims.has_live_combat()


## Advance every live skirmish by one fixed combat step. Always bumps
## `combat_step` so replays can step to a stamped combat step deterministically.
func step_combat() -> void:
	combat_step += 1
	claims.step_combat(self)


## Remove a unit that died in combat. Its view frees itself when the unit is gone.
func kill_unit(unit_id: int) -> bool:
	if playable == null:
		return false
	var unit: SimUnit = playable.get_unit(unit_id)
	if unit == null:
		return false
	var faction_id: StringName = unit.faction_id
	playable.units.erase(unit_id)
	EventBus.unit_killed.emit(unit_id, faction_id)
	return true


func capture_building(building_id: int, new_faction_id: StringName) -> bool:
	if playable == null:
		return false
	var building: SimBuilding = playable.get_building(building_id)
	var new_faction: SimFaction = get_faction(new_faction_id)
	if building == null or new_faction == null or building.faction_id == new_faction_id:
		return false
	var previous: StringName = building.faction_id
	building.faction_id = new_faction_id
	EventBus.structure_captured.emit(building.id, previous, new_faction_id)
	claims.update(self)
	return true


func destroy_building(building_id: int) -> bool:
	if playable == null:
		return false
	var building: SimBuilding = playable.get_building(building_id)
	if building == null or building.building_type == SimIds.TOWN_CENTER:
		return false
	var faction_id: StringName = building.faction_id
	var building_type: StringName = building.building_type
	var cell: Vector2i = building.grid_pos
	playable.remove_building(building_id)
	EventBus.structure_destroyed.emit(building_id, faction_id, building_type, cell)
	claims.update(self)
	return true


func configure_seed(p_seed: int) -> void:
	rng_seed = p_seed
	rng = RandomNumberGenerator.new()
	rng.seed = p_seed


func randi() -> int:
	return rng.randi()


func randf() -> float:
	return rng.randf()


func eras_for_faction(faction: SimFaction) -> Array[EraData]:
	if faction != null and faction.species != null:
		var track: Variant = species_eras.get(faction.species.species_id, null)
		if track != null:
			var out: Array[EraData] = []
			for era in track:
				out.append(era as EraData)
			return out
	return eras


func world_era() -> EraData:
	return SimCatalog.era_by_index(eras, world_era_index)


func _advance_world_era() -> void:
	if world_era_index >= 3:
		return
	world_era_elapsed += 1
	if world_era_elapsed < SimCatalog.WORLD_ERA_INTERVAL:
		return
	world_era_elapsed = 0
	var previous: EraData = world_era()
	world_era_index += 1
	var next_era: EraData = world_era()
	EventBus.world_era_changed.emit(world_era_index, next_era, previous)


func faction_eliminated(faction_id: StringName) -> bool:
	if playable == null:
		return true
	if not playable.units_for(faction_id).is_empty():
		return false
	for building: SimBuilding in playable.buildings_for(faction_id):
		return false
	return get_faction(faction_id) != null


func eliminate_faction(faction_id: StringName) -> bool:
	if playable == null or get_faction(faction_id) == null:
		return false
	var unit_ids: Array[int] = []
	for unit: SimUnit in playable.units_for(faction_id):
		unit_ids.append(unit.id)
	for unit_id: int in unit_ids:
		playable.units.erase(unit_id)
	var building_ids: Array[int] = []
	for building: SimBuilding in playable.buildings_for(faction_id):
		building_ids.append(building.id)
	for building_id: int in building_ids:
		playable.remove_building(building_id)
	claims.update(self)
	return true


func state_hash() -> int:
	var parts: PackedStringArray = PackedStringArray()
	parts.append("tick=%d" % current_tick)
	parts.append("world_era=%d" % world_era_index)
	parts.append("seed=%d" % rng_seed)
	parts.append("combat_step=%d" % combat_step)
	parts.append("rng=%d" % rng.state)
	var ids: Array[StringName] = faction_ids()
	ids.sort()
	for faction_id: StringName in ids:
		var faction: SimFaction = get_faction(faction_id)
		var era_index: int = -1 if faction.era == null else faction.era.era_index
		var era_name: String = "" if faction.era == null else faction.era.era_name
		parts.append("f:%s:era=%d:%s" % [String(faction_id), era_index, era_name])
		var res_ids: Array[StringName] = SimIds.all_resources()
		for resource_id: StringName in res_ids:
			parts.append("r:%s:%s=%d" % [String(faction_id), String(resource_id), faction.get_resource(resource_id)])
	if playable != null:
		var b_ids: Array[int] = []
		for bid in playable.buildings.keys():
			b_ids.append(int(bid))
		b_ids.sort()
		for bid: int in b_ids:
			var building: SimBuilding = playable.get_building(bid)
			parts.append("b:%d:%s:%s:%d:%d:%d:%d" % [
				building.id, String(building.faction_id), String(building.building_type),
				building.grid_pos.x, building.grid_pos.y, int(building.constructed), building.hp
			])
		var u_ids: Array[int] = []
		for uid in playable.units.keys():
			u_ids.append(int(uid))
		u_ids.sort()
		for uid: int in u_ids:
			var unit: SimUnit = playable.get_unit(uid)
			var px: int = int(round(unit.position.x * 10000.0))
			var pz: int = int(round(unit.position.z * 10000.0))
			parts.append("u:%d:%s:%s:%d:%d:%d:%s" % [
				unit.id, String(unit.faction_id), String(unit.unit_type), px, pz, unit.hp, String(unit.assigned_node_id)
			])
		var claim_keys: Array[int] = []
		for key in playable.hex_claims.keys():
			claim_keys.append(int(key))
		claim_keys.sort()
		for key: int in claim_keys:
			parts.append("h:%d=%s" % [key, String(playable.hex_claims[key])])
		var node_ids: Array[String] = []
		for nid in playable.nodes.keys():
			node_ids.append(String(nid))
		node_ids.sort()
		for nid: String in node_ids:
			var node: SimResourceNode = playable.get_node(StringName(nid))
			parts.append("n:%s=%d:%s" % [nid, node.remaining, String(node.hard_claimer)])
	var joined: String = "|".join(parts)
	return hash(joined)
