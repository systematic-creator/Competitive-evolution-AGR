class_name FactionAI
extends RefCounted
## Personality-weighted AI for Sylvari, Kraal, and Cogforged (and any AI faction).

const BUILD_PRIORITY: Array[StringName] = [
	SimIds.FARM,
	SimIds.LUMBER_CAMP,
	SimIds.QUARRY,
	SimIds.HOUSE,
	SimIds.FOUNDRY,
	SimIds.BARRACKS,
]


func act(world: SimWorld, faction: SimFaction, tick: int) -> void:
	if faction == null or faction.is_player():
		return
	var species: SpeciesData = faction.species
	var region: SimRegion = world.playable
	_assign_idle_workers(world, faction, region, species)
	if species != null and species.can_build_extractors:
		_consider_extractor(world, faction, region, species)
	# Era first when the personality heavily favors it and the cost is payable.
	if species != null and species.ai_era_weight >= 1.2:
		if world.upgrades.can_advance_era(world, faction):
			if _roll(species.ai_era_weight, 1.15):
				world.try_advance_era(faction.faction_id())
				return
	if _want(species, species.ai_expand_weight if species else 1.0, 0.7) or tick % 2 == 0:
		_consider_buildings(world, faction, region, species)
	if _want(species, species.ai_economy_weight if species else 1.0, 0.6):
		_consider_workers(world, faction, species)
	if _want(species, species.ai_military_weight if species else 1.0, 0.85):
		_consider_soldiers(world, faction, species)
	if _want(species, species.ai_era_weight if species else 1.0, 1.0):
		world.try_advance_era(faction.faction_id())
	if _want(species, species.ai_military_weight if species else 1.0, 0.9):
		_move_soldiers(world, faction, region)


func _want(species: SpeciesData, weight: float, threshold: float) -> bool:
	if species == null:
		return weight >= threshold
	return weight >= threshold


func _roll(weight: float, threshold: float) -> bool:
	return weight >= threshold


func _consider_buildings(world: SimWorld, faction: SimFaction, region: SimRegion, species: SpeciesData) -> void:
	var types: Array[StringName] = BUILD_PRIORITY.duplicate()
	# Personality reshuffle: Cogforged wants a Foundry early; Sylvari delays barracks;
	# Kraal wants houses (pop for the swarm) sooner.
	if species != null and species.units_are_constructed:
		types.erase(SimIds.FOUNDRY)
		types.insert(0, SimIds.FOUNDRY)
	if species != null and species.ai_defense_weight >= 1.4:
		types.erase(SimIds.BARRACKS)
		types.append(SimIds.BARRACKS)
	if species != null and species.ai_expand_weight >= 1.4:
		types.erase(SimIds.HOUSE)
		types.insert(1, SimIds.HOUSE)
	var fid: StringName = faction.faction_id()
	for building_type: StringName in types:
		if building_type == SimIds.HOUSE:
			if region.population(fid) + 1 < region.population_cap(fid) and species != null and species.ai_expand_weight < 1.3:
				continue
		elif building_type == SimIds.BARRACKS or building_type == SimIds.FOUNDRY:
			if region.completed_count(fid, building_type) >= 1:
				continue
		else:
			var cap: int = 2 if (species != null and species.ai_economy_weight >= 1.2) else 1
			if region.completed_count(fid, building_type) + _under_construction(region, fid, building_type) >= cap:
				continue
		if not faction.can_afford(SimCatalog.building_cost(building_type)):
			continue
		var cell: Vector2i = _pick_build_cell(region, fid, building_type, species)
		if cell.x < 0:
			continue
		if world.place_building(fid, building_type, cell) >= 0:
			return


func _under_construction(region: SimRegion, faction_id: StringName, building_type: StringName) -> int:
	var n: int = 0
	for building: SimBuilding in region.buildings_for(faction_id):
		if not building.constructed and building.building_type == building_type:
			n += 1
	return n


func _consider_workers(world: SimWorld, faction: SimFaction, species: SpeciesData) -> void:
	var region: SimRegion = world.playable
	var fid: StringName = faction.faction_id()
	if region.population(fid) >= region.population_cap(fid):
		return
	# Slow-growth species (Cogforged) train less often; swarms (Kraal) try every tick.
	var expand: float = 1.0 if species == null else species.ai_expand_weight
	if expand < 0.8 and region.units_for(fid).size() >= 4:
		return
	world.queue_training(fid, SimIds.WORKER)


func _consider_soldiers(world: SimWorld, faction: SimFaction, species: SpeciesData) -> void:
	var region: SimRegion = world.playable
	var fid: StringName = faction.faction_id()
	var trainer: StringName = SimCatalog.trainer_for(SimIds.SOLDIER, species)
	if region.completed_count(fid, trainer) < 1 and region.completed_count(fid, SimIds.BARRACKS) < 1:
		return
	if region.population(fid) >= region.population_cap(fid):
		return
	var soldiers: int = 0
	for unit: SimUnit in region.units_for(fid):
		if unit.unit_type == SimIds.SOLDIER:
			soldiers += 1
	var cap: int = 4 if (species != null and species.ai_military_weight >= 1.4) else 2
	if soldiers >= cap:
		return
	world.queue_training(fid, SimIds.SOLDIER)


func _assign_idle_workers(world: SimWorld, faction: SimFaction, region: SimRegion, species: SpeciesData) -> void:
	var fid: StringName = faction.faction_id()
	var need: StringName = _needed_resource(world, faction, species)
	if species != null and species.ai_rare_weight >= 1.2:
		# Keep at least one worker on a *visible* rare node whenever one still has yield.
		var rare_workers: int = 0
		for unit: SimUnit in region.units_for(fid):
			if unit.unit_type != SimIds.WORKER:
				continue
			var assigned: SimResourceNode = region.get_node(unit.assigned_node_id)
			if assigned != null and assigned.is_rare() and assigned.remaining > 0 and world.can_see_node(fid, assigned):
				rare_workers += 1
		if rare_workers == 0:
			if world.can_see_resource(fid, SimIds.IRON) and faction.get_resource(SimIds.IRON) <= faction.get_resource(SimIds.COAL):
				need = SimIds.IRON
			elif world.can_see_resource(fid, SimIds.COAL):
				need = SimIds.COAL
	for unit: SimUnit in region.units_for(fid):
		if unit.unit_type != SimIds.WORKER:
			continue
		if unit.assigned_node_id != &"":
			var existing: SimResourceNode = region.get_node(unit.assigned_node_id)
			if existing != null and existing.is_rare() and not world.can_see_node(fid, existing):
				unit.assigned_node_id = &""
				unit.has_destination = false
		if unit.assigned_node_id != &"" and unit.has_destination:
			continue
		if unit.assigned_node_id != &"":
			var existing: SimResourceNode = region.get_node(unit.assigned_node_id)
			if existing != null and existing.remaining > 0 and world.can_see_node(fid, existing):
				continue
		var node: SimResourceNode = _nearest_node(world, region, unit.position, need, species, fid)
		if node == null:
			node = _nearest_node(world, region, unit.position, &"", species, fid)
		if node != null:
			world.order_gather(unit.id, node.node_id)


func _needed_resource(world: SimWorld, faction: SimFaction, species: SpeciesData) -> StringName:
	var rare_weight: float = 1.0 if species == null else species.ai_rare_weight
	var fid: StringName = faction.faction_id()
	# Contest only rare nodes this faction has revealed.
	if rare_weight >= 1.0 and world.can_see_resource(fid, SimIds.IRON) and faction.get_resource(SimIds.IRON) < 16:
		return SimIds.IRON
	if rare_weight >= 1.0 and world.can_see_resource(fid, SimIds.COAL) and faction.get_resource(SimIds.COAL) < 12:
		return SimIds.COAL
	if species != null and species.units_are_constructed:
		if faction.get_resource(SimIds.STONE) <= faction.get_resource(SimIds.WOOD):
			return SimIds.STONE
		return SimIds.WOOD
	if faction.get_resource(SimIds.FOOD) < 40:
		return SimIds.FOOD
	if faction.get_resource(SimIds.WOOD) < 40:
		return SimIds.WOOD
	return SimIds.STONE


func _nearest_node(world: SimWorld, region: SimRegion, from: Vector3, resource_id: StringName, species: SpeciesData, faction_id: StringName) -> SimResourceNode:
	var best: SimResourceNode = null
	var best_score: float = INF
	var rare_weight: float = 1.0 if species == null else species.ai_rare_weight
	for node: SimResourceNode in region.nodes.values():
		if node.remaining <= 0:
			continue
		if not world.can_see_node(faction_id, node):
			continue
		if resource_id != &"" and node.resource_id() != resource_id:
			continue
		var score: float = from.distance_to(node.position)
		if node.is_rare():
			score /= maxf(0.35, rare_weight)
		elif species != null and species.ai_defense_weight >= 1.3:
			if region.owner_at(node.cell) == &"":
				score *= 1.15
		if score < best_score:
			best = node
			best_score = score
	return best


func _pick_build_cell(region: SimRegion, faction_id: StringName, building_type: StringName, species: SpeciesData) -> Vector2i:
	var origin := Vector2i(region.grid_size().x / 2, region.grid_size().y / 2)
	for building: SimBuilding in region.buildings_for(faction_id):
		if building.building_type == SimIds.TOWN_CENTER:
			origin = building.grid_pos
			break
	# Tight spiral for defensive / slow expanders; wider ring for swarms.
	var max_r: int = 8 if (species != null and species.ai_expand_weight >= 1.4) else 6
	if species != null and species.ai_defense_weight >= 1.4:
		max_r = 5
	for radius: int in range(1, max_r + 1):
		for dx: int in range(-radius, radius + 1):
			for dy: int in range(-radius, radius + 1):
				if maxi(abs(dx), abs(dy)) != radius:
					continue
				var cell: Vector2i = origin + Vector2i(dx, dy)
				if region.can_place(cell, building_type, false):
					return cell
	return Vector2i(-1, -1)


func _consider_extractor(world: SimWorld, faction: SimFaction, region: SimRegion, species: SpeciesData) -> void:
	if not faction.can_afford(SimCatalog.building_cost(SimIds.EXTRACTOR)):
		return
	var cell: Vector2i = _pick_extractor_cell(world, region, faction.faction_id())
	if cell.x < 0:
		return
	world.place_building(faction.faction_id(), SimIds.EXTRACTOR, cell)


func _pick_extractor_cell(world: SimWorld, region: SimRegion, faction_id: StringName) -> Vector2i:
	for node: SimResourceNode in region.nodes.values():
		if not node.is_rare() or node.remaining <= 0 or not world.can_see_node(faction_id, node):
			continue
		if _has_extractor_near(region, faction_id, node.cell):
			continue
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
			var cell: Vector2i = node.cell + offset
			if region.can_place(cell, SimIds.EXTRACTOR, false):
				return cell
	return Vector2i(-1, -1)


func _has_extractor_near(region: SimRegion, faction_id: StringName, cell: Vector2i) -> bool:
	for building: SimBuilding in region.buildings_for(faction_id):
		if building.building_type != SimIds.EXTRACTOR:
			continue
		if maxi(abs(building.grid_pos.x - cell.x), abs(building.grid_pos.y - cell.y)) == 1:
			return true
	return false


func _move_soldiers(world: SimWorld, faction: SimFaction, region: SimRegion) -> void:
	var fid: StringName = faction.faction_id()
	var target := _rare_contest_point(world, region, fid)
	for unit: SimUnit in region.units_for(fid):
		if unit.unit_type != SimIds.SOLDIER and unit.unit_type != SimIds.IRONCLAD and unit.unit_type != SimIds.STEAMWALKER:
			continue
		if unit.has_destination and unit.position.distance_to(unit.destination) > region.cell_size() * 0.5:
			continue
		world.order_move(unit.id, target)


func _rare_contest_point(world: SimWorld, region: SimRegion, faction_id: StringName) -> Vector3:
	var best: SimResourceNode = null
	var best_score: float = INF
	for node: SimResourceNode in region.nodes.values():
		if not node.is_rare() or node.remaining <= 0 or not world.can_see_node(faction_id, node):
			continue
		var owner: StringName = region.owner_at(node.cell)
		var score: float = 1.0 if owner == faction_id else 0.4
		if owner != &"" and owner != faction_id:
			score = 0.25
		if score < best_score:
			best = node
			best_score = score
	if best != null:
		return best.position
	return Vector3.ZERO
