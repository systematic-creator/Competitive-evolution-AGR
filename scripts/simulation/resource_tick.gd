class_name ResourceTick
extends RefCounted
## Per-tick gathering, building output, depletion, Sylvari common-node
## regrowth, and Cogforged extractor bonuses on rare nodes.


func apply(world: SimWorld) -> void:
	var region: SimRegion = world.playable
	if region == null:
		return
	_gather(world, region)
	_extractor_trickle(world, region)
	_building_output(world, region)
	_sylvari_regen(world, region)


func _gather(world: SimWorld, region: SimRegion) -> void:
	for unit: SimUnit in region.units.values():
		if unit.unit_type != SimIds.WORKER or unit.assigned_node_id == &"":
			continue
		var node: SimResourceNode = region.get_node(unit.assigned_node_id)
		if node == null or node.remaining <= 0:
			unit.assigned_node_id = &""
			continue
		if unit.position.distance_to(node.position) > region.cell_size() * 1.6:
			continue
		if not world.can_see_node(unit.faction_id, node):
			unit.assigned_node_id = &""
			continue
		var faction: SimFaction = world.get_faction(unit.faction_id)
		if faction == null:
			continue
		var yield_amount: int = 0
		var deplete_amount: int = 0
		var amounts: Dictionary = _compute_gather(node, faction, region, world)
		yield_amount = int(amounts["yield"])
		deplete_amount = int(amounts["deplete"])
		if yield_amount <= 0 and deplete_amount <= 0:
			continue
		node.remaining = maxi(0, node.remaining - deplete_amount)
		if yield_amount > 0:
			faction.add_resource(node.resource_id(), yield_amount)


func _compute_gather(node: SimResourceNode, faction: SimFaction, region: SimRegion, world: SimWorld) -> Dictionary:
	var species: SpeciesData = faction.species
	var era_mult: float = 1.0 if faction.era == null else faction.era.production_multiplier
	var gather_mult: float = 1.0 if species == null else species.gather_rate_multiplier
	var harvest: float = 1.0 if species == null else species.harvest_speed_multiplier
	var extractor: float = 1.0 + world.extractor_bonus_for(region, node, faction.faction_id())
	var raw: float = float(node.base_gather()) * era_mult * gather_mult * harvest * extractor
	var yield_amount: int = maxi(1, int(round(raw)))
	# Rare yield is split by claimed-hex share only. Occupying a hex is not enough.
	if node.is_rare():
		yield_amount = world.claims.yield_for(region, node, faction.faction_id(), yield_amount)
		if yield_amount <= 0:
			var empty: Dictionary = {"yield": 0, "deplete": 0}
			return empty
	var depletion: float = 1.0 if species == null else species.node_depletion_multiplier
	var deplete_amount: int = maxi(yield_amount, int(round(float(yield_amount) * depletion)))
	if deplete_amount > node.remaining:
		if depletion > 0.0:
			yield_amount = maxi(0, int(floor(float(node.remaining) / depletion)))
		else:
			yield_amount = node.remaining
		deplete_amount = node.remaining
	var out: Dictionary = {"yield": yield_amount, "deplete": deplete_amount}
	return out


func _extractor_trickle(world: SimWorld, region: SimRegion) -> void:
	# Constructed extractors slowly pull rare resources for their owner.
	for building: SimBuilding in region.buildings.values():
		if not building.constructed or building.building_type != SimIds.EXTRACTOR:
			continue
		var faction: SimFaction = world.get_faction(building.faction_id)
		if faction == null or faction.species == null or not faction.species.can_build_extractors:
			continue
		for node: SimResourceNode in region.nodes.values():
			if not node.is_rare() or node.remaining <= 0:
				continue
			if not world.can_see_node(building.faction_id, node):
				continue
			if not _is_adjacent(building.grid_pos, node.cell):
				continue
			var amount: int = maxi(1, int(round(1.0 + faction.species.extractor_rare_yield_bonus)))
			amount = world.claims.yield_for(region, node, building.faction_id, amount)
			amount = mini(amount, node.remaining)
			if amount <= 0:
				continue
			node.remaining -= amount
			faction.add_resource(node.resource_id(), amount)


func _is_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return maxi(abs(a.x - b.x), abs(a.y - b.y)) == 1 or (abs(a.x - b.x) + abs(a.y - b.y) == 1)


func _building_output(world: SimWorld, region: SimRegion) -> void:
	for building: SimBuilding in region.buildings.values():
		if not building.constructed:
			continue
		var faction: SimFaction = world.get_faction(building.faction_id)
		if faction == null:
			continue
		var species: SpeciesData = faction.species
		var era_mult: float = 1.0 if faction.era == null else faction.era.production_multiplier
		var industry: float = 1.0 if species == null else (1.0 + species.industry_production_bonus)
		var scale: float = era_mult * industry
		match building.building_type:
			SimIds.TOWN_CENTER:
				faction.add_resource(SimIds.FOOD, maxi(1, int(round(1.0 * scale))))
			SimIds.FARM:
				faction.add_resource(SimIds.FOOD, maxi(1, int(round(4.0 * era_mult * (1.0 if species == null else species.gather_rate_multiplier)))))
			SimIds.LUMBER_CAMP:
				faction.add_resource(SimIds.WOOD, maxi(1, int(round(3.0 * scale))))
			SimIds.QUARRY:
				faction.add_resource(SimIds.STONE, maxi(1, int(round(3.0 * scale))))
			SimIds.FOUNDRY:
				faction.add_resource(SimIds.WOOD, maxi(1, int(round(2.0 * scale))))
				faction.add_resource(SimIds.STONE, maxi(1, int(round(3.0 * scale))))
			_:
				pass


func _sylvari_regen(world: SimWorld, region: SimRegion) -> void:
	for node: SimResourceNode in region.nodes.values():
		if node.is_rare():
			continue
		var owner_id: StringName = region.owner_at(node.cell)
		if owner_id == &"":
			continue
		var faction: SimFaction = world.get_faction(owner_id)
		if faction == null or faction.species == null:
			continue
		var regen: int = faction.species.territory_regen_per_tick
		if regen <= 0:
			continue
		node.remaining = mini(node.capacity, node.remaining + regen)
