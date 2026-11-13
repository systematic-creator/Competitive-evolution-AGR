class_name BuildingUpgradeSystem
extends RefCounted
## Construction progress and era-advancement rules.


func progress_construction(world: SimWorld) -> void:
	var region: SimRegion = world.playable
	if region == null:
		return
	for building: SimBuilding in region.buildings.values():
		if building.constructed:
			continue
		var faction: SimFaction = world.get_faction(building.faction_id)
		var speed: float = 1.0 if faction == null or faction.species == null else faction.species.build_speed_multiplier
		building.build_progress += speed
		if building.build_progress + 0.0001 >= float(building.build_ticks_required):
			building.constructed = true
			building.build_progress = float(building.build_ticks_required)
			EventBus.building_constructed.emit(
				building.faction_id, building.id, building.building_type, building.grid_pos
			)
	world.claims.update(world)


func progress_training(world: SimWorld) -> void:
	var region: SimRegion = world.playable
	if region == null:
		return
	for faction_id: StringName in world.faction_ids():
		var faction: SimFaction = world.get_faction(faction_id)
		if faction.pending_trains.is_empty():
			continue
		var still_pending: Array[Dictionary] = []
		for job: Dictionary in faction.pending_trains:
			var remaining: int = int(job.get("ticks", 1)) - 1
			if remaining <= 0:
				var unit_type: StringName = job.get("unit_type", SimIds.WORKER) as StringName
				var at_id: int = int(job.get("building_id", 0))
				world.spawn_trained_unit(faction_id, unit_type, at_id)
			else:
				job["ticks"] = remaining
				still_pending.append(job)
		faction.pending_trains = still_pending


func can_advance_era(world: SimWorld, faction: SimFaction) -> bool:
	if faction == null or faction.era == null:
		return false
	var next_index: int = faction.era.era_index + 1
	var next_era: EraData = SimCatalog.era_by_index(world.eras, next_index)
	if next_era == null:
		return false
	if world.playable.population(faction.faction_id()) < SimCatalog.era_advance_min_pop(next_index):
		return false
	return faction.can_afford(SimCatalog.era_advance_cost(next_index, faction.species))


func advance_era(world: SimWorld, faction: SimFaction) -> bool:
	if not can_advance_era(world, faction):
		return false
	var previous: EraData = faction.era
	var next_index: int = previous.era_index + 1
	var next_era: EraData = SimCatalog.era_by_index(world.eras, next_index)
	if not faction.pay(SimCatalog.era_advance_cost(next_index, faction.species)):
		return false
	faction.era = next_era
	EventBus.era_changed.emit(faction.faction_id(), next_era, previous)
	return true
