class_name ClaimSystem
extends RefCounted
## Escalation ladder and hex claims.
## Structures CLAIM hexes (claims radiate from constructed buildings).
## Units OCCUPY hexes (presence, block enemy claiming, enable skirmishes).
## Yield share counts claimed hexes only. Capturing or destroying a structure
## releases its claim.

const CLUSTER_RADIUS: int = 1
const SKIRMISH_SQUAD_CAP: int = 3
const STRUCTURE_DEFENSE: float = 0.75

var next_skirmish_id: int = 1
## skirmish_id -> Dictionary
var pending: Dictionary = {}


func update(world: SimWorld) -> void:
	if world == null or world.playable == null:
		return
	var region: SimRegion = world.playable
	refresh_occupation(region)
	_rebuild_claims(world, region)
	_update_node_claims(world, region)


func refresh_occupation(region: SimRegion) -> void:
	region.hex_occupants.clear()
	for unit: SimUnit in region.units.values():
		if unit.hp <= 0:
			continue
		var hex: Vector2i = region.hex_at_world(unit.position)
		var key: int = HexGrid.pack(hex)
		if not region.hex_occupants.has(key):
			var ids: Array[int] = []
			region.hex_occupants[key] = ids
		(region.hex_occupants[key] as Array).append(unit.id)


func _rebuild_claims(world: SimWorld, region: SimRegion) -> void:
	var next_claims: Dictionary = {}
	var next_source: Dictionary = {}
	var next_dist: Dictionary = {}
	for building: SimBuilding in region.buildings.values():
		if not building.constructed:
			continue
		var radius: int = SimCatalog.building_territory_radius(building.building_type)
		var origin: Vector2i = region.hex_at_world(region.cell_to_world(building.grid_pos))
		for hex: Vector2i in region.hex_grid.hexes_in_radius(origin, radius):
			if region.is_hex_occupied_by_enemy(hex, building.faction_id):
				continue
			var key: int = HexGrid.pack(hex)
			var dist: int = region.hex_grid.distance(origin, hex)
			if next_claims.has(key):
				var existing: int = int(next_dist[key])
				if dist > existing:
					continue
				if dist == existing and (next_claims[key] as StringName) != building.faction_id:
					# Equal-distance contested hex: neither structure claims it.
					next_claims.erase(key)
					next_source.erase(key)
					next_dist.erase(key)
					continue
			next_claims[key] = building.faction_id
			next_source[key] = building.id
			next_dist[key] = dist
	var next_holds: Dictionary = {}
	for key: int in next_claims:
		var fid: StringName = next_claims[key] as StringName
		if region.hex_claims.get(key, &"") == fid:
			next_holds[key] = int(region.hex_hold_ticks.get(key, 0)) + 1
		else:
			next_holds[key] = 1
			var hex: Vector2i = HexGrid.unpack(key)
			EventBus.hex_claimed.emit(fid, hex, int(next_source[key]))
	for key: int in region.hex_claims:
		if not next_claims.has(key):
			var previous: StringName = region.hex_claims[key] as StringName
			EventBus.hex_claim_released.emit(previous, HexGrid.unpack(key), int(region.hex_claim_building.get(key, -1)))
	region.hex_claims = next_claims
	region.hex_claim_building = next_source
	region.hex_hold_ticks = next_holds
	# Keep square-cell owners in sync so older owner_at callers stay accurate.
	region.owners.clear()
	region.hold_ticks.clear()
	var size: Vector2i = region.grid_size()
	for x: int in size.x:
		for y: int in size.y:
			var cell := Vector2i(x, y)
			var fid: StringName = region.hex_owner_at_world(region.cell_to_world(cell))
			if fid == &"":
				continue
			var packed: int = region.pack_cell(cell)
			region.owners[packed] = fid
			region.hold_ticks[packed] = region.hex_hold_ticks_at_world(region.cell_to_world(cell))


func _update_node_claims(world: SimWorld, region: SimRegion) -> void:
	for node: SimResourceNode in region.nodes.values():
		if not node.is_rare():
			continue
		var previous_soft: StringName = node.soft_claimer
		var previous_hard: StringName = node.hard_claimer
		var previous_outpost: int = node.claimed_outpost_id
		var center_owner: StringName = region.hex_owner(node.hex)
		node.soft_claimer = center_owner
		var outpost: SimBuilding = _outpost_for_node(region, node)
		if outpost != null:
			node.hard_claimer = outpost.faction_id
			node.claimed_outpost_id = outpost.id
		else:
			node.hard_claimer = &""
			node.claimed_outpost_id = -1
		if node.soft_claimer != previous_soft:
			if node.soft_claimer != &"":
				EventBus.node_claimed.emit(node.soft_claimer, node.node_id, &"soft")
			elif previous_soft != &"":
				EventBus.node_claim_lost.emit(previous_soft, node.node_id, &"soft")
		if node.hard_claimer != previous_hard or node.claimed_outpost_id != previous_outpost:
			if node.hard_claimer != &"":
				EventBus.node_claimed.emit(node.hard_claimer, node.node_id, &"hard")
				EventBus.outpost_established.emit(
					node.hard_claimer, node.claimed_outpost_id, node.node_id, outpost.grid_pos
				)
			elif previous_hard != &"":
				EventBus.node_claim_lost.emit(previous_hard, node.node_id, &"hard")


func _outpost_for_node(region: SimRegion, node: SimResourceNode) -> SimBuilding:
	var best: SimBuilding = null
	var best_dist: int = 99
	for building: SimBuilding in region.buildings.values():
		if not building.constructed or building.building_type != SimIds.OUTPOST:
			continue
		var bhex: Vector2i = region.hex_at_cell(building.grid_pos)
		var dist: int = region.hex_grid.distance(bhex, node.hex)
		if dist > 1:
			continue
		if dist < best_dist:
			best = building
			best_dist = dist
	return best


func cluster_hexes(region: SimRegion, node: SimResourceNode) -> Array[Vector2i]:
	if node == null or region == null or region.hex_grid == null:
		var empty: Array[Vector2i] = []
		return empty
	return region.hex_grid.hexes_in_radius(node.hex, CLUSTER_RADIUS)


func claimed_hex_count(region: SimRegion, node: SimResourceNode, faction_id: StringName) -> int:
	var n: int = 0
	for hex: Vector2i in cluster_hexes(region, node):
		if region.hex_owner(hex) == faction_id:
			n += 1
	return n


func yield_share(region: SimRegion, node: SimResourceNode, faction_id: StringName) -> float:
	var total: int = cluster_hexes(region, node).size()
	if total <= 0:
		return 0.0
	return float(claimed_hex_count(region, node, faction_id)) / float(total)


func has_full_control(region: SimRegion, node: SimResourceNode, faction_id: StringName) -> bool:
	var cluster: Array[Vector2i] = cluster_hexes(region, node)
	if cluster.is_empty() or faction_id == &"":
		return false
	for hex: Vector2i in cluster:
		if region.hex_owner(hex) != faction_id:
			return false
	return true


## Split `amount` by claimed-hex share. Unclaimed hexes withhold their portion.
## Full control (every cluster hex claimed) returns the whole amount.
func yield_for(region: SimRegion, node: SimResourceNode, faction_id: StringName, amount: int) -> int:
	if node == null or not node.is_rare():
		return amount
	var total: int = cluster_hexes(region, node).size()
	var claimed: int = claimed_hex_count(region, node, faction_id)
	if claimed <= 0 or total <= 0 or amount <= 0:
		return 0
	if claimed >= total:
		return amount
	return int(floor(float(amount) * float(claimed) / float(total) + 0.000001))


func rare_node_for_hex(region: SimRegion, hex: Vector2i) -> SimResourceNode:
	for node: SimResourceNode in region.nodes.values():
		if not node.is_rare():
			continue
		if region.hex_grid.distance(node.hex, hex) <= CLUSTER_RADIUS:
			return node
	return null


func is_near_visible_rare(world: SimWorld, faction_id: StringName, cell: Vector2i) -> bool:
	var region: SimRegion = world.playable
	var cell_hex: Vector2i = region.hex_at_cell(cell)
	for node: SimResourceNode in region.nodes.values():
		if not node.is_rare() or not world.can_see_node(faction_id, node):
			continue
		if region.hex_grid.distance(cell_hex, node.hex) <= 1:
			return true
	return false


func start_skirmish(world: SimWorld, attacker_id: StringName, node_id: StringName, hex: Vector2i, auto_battle: bool) -> int:
	if world == null or world.playable == null:
		return -1
	refresh_occupation(world.playable)
	var node: SimResourceNode = world.playable.get_node(node_id)
	if node == null or not node.is_rare():
		return -1
	if not world.can_see_node(attacker_id, node):
		return -1
	if world.playable.hex_grid.distance(node.hex, hex) > CLUSTER_RADIUS:
		return -1
	if not _faction_occupies_hex(world.playable, attacker_id, hex, true):
		return -1
	var defender_id: StringName = _defender_for(world.playable, hex)
	if defender_id == attacker_id:
		return -1
	var sid: int = next_skirmish_id
	next_skirmish_id += 1
	var record: Dictionary = {
		"id": sid,
		"attacker": attacker_id,
		"defender": defender_id,
		"node_id": node_id,
		"hex_key": HexGrid.pack(hex),
		"resolved": false,
	}
	pending[sid] = record
	EventBus.skirmish_started.emit(sid, attacker_id, defender_id, node_id, hex)
	if auto_battle:
		resolve_auto_battle(world, sid)
	else:
		EventBus.skirmish_possession_requested.emit(sid, attacker_id, node_id, hex)
	return sid


func resolve_auto_battle(world: SimWorld, skirmish_id: int) -> bool:
	if not pending.has(skirmish_id):
		return false
	var record: Dictionary = pending[skirmish_id] as Dictionary
	if bool(record.get("resolved", false)):
		return false
	var combat: SkirmishCombat = record.get("combat", null) as SkirmishCombat
	if combat != null:
		# Auto-battle fallback during (or after) a possession fight: settle it
		# from what is left on the field instead of the opening squads.
		var verdict: StringName = combat.winner_id if combat.finished else combat.decide_by_strength(world)
		_finish_skirmish(world, record, verdict)
		return true
	refresh_occupation(world.playable)
	var hex: Vector2i = HexGrid.unpack(int(record.get("hex_key", 0)))
	var attacker_id: StringName = record["attacker"] as StringName
	var defender_id: StringName = record["defender"] as StringName
	var attack: float = _squad_strength(world, attacker_id, hex, false)
	var defense: float = _squad_strength(world, defender_id, hex, true)
	var winner: StringName = attacker_id if attack > defense else defender_id
	_finish_skirmish(world, record, winner)
	return true


func _finish_skirmish(world: SimWorld, record: Dictionary, winner: StringName) -> void:
	var skirmish_id: int = int(record.get("id", -1))
	var hex: Vector2i = HexGrid.unpack(int(record.get("hex_key", 0)))
	var attacker_id: StringName = record["attacker"] as StringName
	var defender_id: StringName = record["defender"] as StringName
	var node_id: StringName = record["node_id"] as StringName
	var loser: StringName = defender_id if winner == attacker_id else attacker_id
	var combat: SkirmishCombat = record.get("combat", null) as SkirmishCombat
	if combat != null:
		combat.release_units(world)
		refresh_occupation(world.playable)
	var flipped: bool = false
	var captured_id: int = -1
	if winner == attacker_id:
		var structure: SimBuilding = _structure_to_capture(world.playable, hex, node_id)
		if structure != null and structure.faction_id != attacker_id:
			world.capture_building(structure.id, attacker_id)
			captured_id = structure.id
			flipped = true
		update(world)
	record["resolved"] = true
	record["winner"] = winner
	record["flipped"] = flipped
	EventBus.skirmish_resolved.emit(skirmish_id, winner, loser, node_id, hex, captured_id, flipped)
	if combat != null:
		EventBus.skirmish_possession_ended.emit(skirmish_id, winner)


# --- Tier 4 possession ------------------------------------------------------

## Attacking squad members the player may possess for a pending skirmish:
## the same (capped) squad auto-battle would field, living and military.
func possession_candidates(world: SimWorld, skirmish_id: int) -> Array[SimUnit]:
	var out: Array[SimUnit] = []
	if world == null or world.playable == null or not pending.has(skirmish_id):
		return out
	var record: Dictionary = pending[skirmish_id] as Dictionary
	if bool(record.get("resolved", false)):
		return out
	var combat: SkirmishCombat = record.get("combat", null) as SkirmishCombat
	if combat != null:
		if combat.finished:
			return out
		return combat.living(world, combat.attackers)
	refresh_occupation(world.playable)
	var hex: Vector2i = HexGrid.unpack(int(record.get("hex_key", 0)))
	return _squad_units(world.playable, record["attacker"] as StringName, hex)


func possess_unit(world: SimWorld, skirmish_id: int, unit_id: int) -> bool:
	if world == null or world.playable == null or not pending.has(skirmish_id):
		return false
	var record: Dictionary = pending[skirmish_id] as Dictionary
	if bool(record.get("resolved", false)):
		return false
	var unit: SimUnit = world.playable.get_unit(unit_id)
	if unit == null or unit.hp <= 0:
		return false
	var combat: SkirmishCombat = record.get("combat", null) as SkirmishCombat
	if combat != null:
		# Re-possess another living attacker (e.g. after the first one fell).
		if combat.finished or not combat.is_attacker_unit(unit_id):
			return false
		combat.possessed_unit_id = unit_id
		combat.steer_sector = -1
		combat.attack_queued = false
		EventBus.skirmish_possession_started.emit(skirmish_id, unit_id)
		return true
	var candidates: Array[SimUnit] = possession_candidates(world, skirmish_id)
	if not candidates.has(unit):
		return false
	var hex: Vector2i = HexGrid.unpack(int(record.get("hex_key", 0)))
	var defender_id: StringName = record["defender"] as StringName
	var defender_units: Array[SimUnit] = []
	if defender_id != &"":
		defender_units = _squad_units(world.playable, defender_id, hex)
	combat = SkirmishCombat.new()
	combat.setup(world, record, candidates, defender_units, unit_id)
	record["combat"] = combat
	EventBus.skirmish_possession_started.emit(skirmish_id, unit_id)
	return true


func steer_possessed(skirmish_id: int, sector: int) -> bool:
	var combat: SkirmishCombat = live_combat(skirmish_id)
	if combat == null or combat.possessed_unit_id < 0:
		return false
	combat.steer_sector = -1 if sector < 0 else posmod(sector, SkirmishCombat.STEER_SECTORS)
	return true


func queue_possessed_attack(skirmish_id: int) -> bool:
	var combat: SkirmishCombat = live_combat(skirmish_id)
	if combat == null or combat.possessed_unit_id < 0:
		return false
	combat.attack_queued = true
	return true


## Settle a possession fight that has finished on the field.
func resolve_possessed(world: SimWorld, skirmish_id: int) -> bool:
	if not pending.has(skirmish_id):
		return false
	var record: Dictionary = pending[skirmish_id] as Dictionary
	var combat: SkirmishCombat = record.get("combat", null) as SkirmishCombat
	if combat == null or not combat.finished or bool(record.get("resolved", false)):
		return false
	_finish_skirmish(world, record, combat.winner_id)
	return true


## The unresolved, still-fighting combat for `skirmish_id`, or null.
func live_combat(skirmish_id: int) -> SkirmishCombat:
	if not pending.has(skirmish_id):
		return null
	var record: Dictionary = pending[skirmish_id] as Dictionary
	if bool(record.get("resolved", false)):
		return null
	var combat: SkirmishCombat = record.get("combat", null) as SkirmishCombat
	if combat == null or combat.finished:
		return null
	return combat


## Any combat (live or finished) attached to an unresolved skirmish.
func combat_for(skirmish_id: int) -> SkirmishCombat:
	if not pending.has(skirmish_id):
		return null
	return (pending[skirmish_id] as Dictionary).get("combat", null) as SkirmishCombat


func has_live_combat() -> bool:
	for sid: int in _sorted_pending_ids():
		if live_combat(sid) != null:
			return true
	return false


func step_combat(world: SimWorld) -> void:
	for sid: int in _sorted_pending_ids():
		var combat: SkirmishCombat = live_combat(sid)
		if combat == null:
			continue
		combat.step(world)
		for event: Dictionary in combat.damage_events:
			EventBus.skirmish_unit_damaged.emit(sid, int(event["unit_id"]), int(event["hp"]), int(event["max_hp"]))
		if not combat.killed_this_step.is_empty():
			refresh_occupation(world.playable)
		EventBus.skirmish_combat_stepped.emit(sid, combat.steps)
		if combat.finished:
			EventBus.skirmish_combat_finished.emit(sid, combat.winner_id)


func _sorted_pending_ids() -> Array[int]:
	var ids: Array[int] = []
	for sid: Variant in pending.keys():
		ids.append(int(sid))
	ids.sort()
	return ids


func _defender_for(region: SimRegion, hex: Vector2i) -> StringName:
	var structure: SimBuilding = region.structure_on_hex(hex)
	if structure != null:
		return structure.faction_id
	var owner: StringName = region.hex_owner(hex)
	if owner != &"":
		return owner
	# Occupied by someone; pick the first non-empty occupant faction via units later.
	return &""


func _faction_occupies_hex(region: SimRegion, faction_id: StringName, hex: Vector2i, military_only: bool) -> bool:
	for unit: SimUnit in region.units_occupying(hex):
		if unit.faction_id != faction_id:
			continue
		if military_only and not SimCatalog.is_military(unit.unit_type):
			continue
		return true
	return false


## Up to SKIRMISH_SQUAD_CAP living military units of `faction_id` on the
## contested hex, then its immediate neighbors (deterministic order).
func _squad_units(region: SimRegion, faction_id: StringName, hex: Vector2i) -> Array[SimUnit]:
	var squad: Array[SimUnit] = []
	if faction_id == &"":
		return squad
	for candidate: Vector2i in region.hex_grid.hexes_in_radius(hex, 1):
		for unit: SimUnit in region.units_occupying(candidate):
			if unit.faction_id != faction_id or not SimCatalog.is_military(unit.unit_type) or unit.hp <= 0:
				continue
			if squad.size() >= SKIRMISH_SQUAD_CAP:
				return squad
			squad.append(unit)
	return squad


func _squad_strength(world: SimWorld, faction_id: StringName, hex: Vector2i, defending: bool) -> float:
	if faction_id == &"":
		return STRUCTURE_DEFENSE if defending and world.playable.structure_on_hex(hex) != null else 0.0
	var region: SimRegion = world.playable
	var strength: float = 0.0
	for unit: SimUnit in _squad_units(region, faction_id, hex):
		var ratio: float = 1.0 if unit.max_hp <= 0 else float(unit.hp) / float(unit.max_hp)
		strength += SimCatalog.unit_combat_power(unit.unit_type) * ratio
	if defending:
		var structure: SimBuilding = region.structure_on_hex(hex)
		if structure != null and structure.faction_id == faction_id:
			strength += STRUCTURE_DEFENSE
		var faction: SimFaction = world.get_faction(faction_id)
		if faction != null and faction.species != null:
			# Hold-time defense (Sylvari) applies to the contested hex.
			var world_pos: Vector3 = region.hex_grid.axial_to_world(hex)
			strength *= region.defense_multiplier(region.world_to_cell(world_pos), faction.species)
	return strength


func find_skirmish_target(world: SimWorld, faction_id: StringName) -> Dictionary:
	refresh_occupation(world.playable)
	var region: SimRegion = world.playable
	for unit: SimUnit in region.units_for(faction_id):
		if not SimCatalog.is_military(unit.unit_type):
			continue
		var hex: Vector2i = region.hex_at_world(unit.position)
		var node: SimResourceNode = rare_node_for_hex(region, hex)
		if node == null or not world.can_see_node(faction_id, node):
			continue
		var defender: StringName = _defender_for(region, hex)
		if defender != &"" and defender != faction_id:
			return {"node_id": node.node_id, "hex": hex}
	return {}


func node_value(node: SimResourceNode, species: SpeciesData) -> float:
	if node == null:
		return 0.0
	var cap: int = maxi(1, node.capacity)
	var value: float = float(node.remaining) / float(cap)
	if node.resource_id() == SimIds.IRON:
		value *= 1.25
	elif node.resource_id() == SimIds.COAL:
		value *= 1.1
	var rare_w: float = 1.0 if species == null else species.ai_rare_weight
	return value * rare_w


func _structure_to_capture(region: SimRegion, hex: Vector2i, node_id: StringName) -> SimBuilding:
	var node: SimResourceNode = region.get_node(node_id)
	if node != null and node.claimed_outpost_id >= 0:
		var outpost: SimBuilding = region.get_building(node.claimed_outpost_id)
		if outpost != null and region.hex_at_cell(outpost.grid_pos) == hex:
			return outpost
	var preferred: SimBuilding = null
	for building: SimBuilding in region.buildings.values():
		if not building.constructed:
			continue
		if region.hex_at_cell(building.grid_pos) != hex:
			continue
		if building.building_type == SimIds.OUTPOST:
			return building
		if preferred == null:
			preferred = building
	return preferred
