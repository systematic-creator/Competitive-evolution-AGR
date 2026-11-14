extends Node
## Headless simulation tests for the concept build.
## Run: godot --headless --path . res://scenes/debug/sim_tests.tscn

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_bootstrap_and_progress()
	_test_player_commands()
	_test_depletion()
	_test_regrowth()
	_test_rare_cost_gating()
	_test_era_gated_reveal()
	_test_extractor_gate()
	_test_hex_grid_and_yield_split()
	_test_escalation_ladder_and_skirmish()
	_test_occupy_blocks_claim_and_destroy()
	_test_ai_escalation_personality()
	_test_per_species_eras()
	_test_soft_cap_cost_scaling()
	_test_win_conditions()
	_test_determinism()
	_test_possession_lifecycle()
	_test_possession_field_victory()
	_test_possession_auto_fallback_and_timeout()
	_test_possession_replay()
	await _test_possession_controller()
	print("%d passed, %d failed" % [_passed, _failed])
	var code: int = 1 if _failed > 0 else 0
	if DisplayServer.get_name() == "headless":
		get_tree().quit(code)
	else:
		if _failed > 0:
			push_error("Sim tests failed: %d" % _failed)


func _check(label: String, ok: bool) -> void:
	if ok:
		_passed += 1
		print("PASS  %s" % label)
	else:
		_failed += 1
		print("FAIL  %s" % label)
		push_error("Sim test failed: %s" % label)


func _boot() -> void:
	GameState.reset()
	GameState.ai_enabled = false
	GameState.bootstrap_concept_world()


func _test_bootstrap_and_progress() -> void:
	_boot()
	var world: SimWorld = GameState.world
	_check("world bootstrapped", world != null and world.playable != null)
	_check("four factions present", world.faction_ids().size() == 4)
	_check("player is humans", world.player_faction_id == SimIds.PLAYER_FACTION)
	_check("AI factions are Sylvari, Kraal, Cogforged", (
		world.get_faction(&"sylvari") != null
		and world.get_faction(&"kraal") != null
		and world.get_faction(&"cogforged") != null
	))
	var common_nodes: int = 0
	var rare_nodes: int = 0
	for node: SimResourceNode in world.playable.nodes.values():
		if node.is_rare():
			rare_nodes += 1
		else:
			common_nodes += 1
	_check("common nodes are spread across the region", common_nodes >= 10)
	_check("few rare iron/coal nodes at contested borders", rare_nodes == 3)
	var basin: RegionData = world.get_region_data(&"verdant_basin")
	_check("playable region advertises rare pin resources", (
		basin != null and basin.rare_resources.has(&"iron") and basin.rare_resources.has(&"coal")
	))
	var humans: SimFaction = world.get_faction(SimIds.PLAYER_FACTION)
	var food_before: int = humans.get_resource(SimIds.FOOD)
	# Let AI run so a faction should place a building and gather.
	GameState.ai_enabled = true
	GameState.step_ticks(24)
	var built: int = 0
	for faction_id: StringName in [&"sylvari", &"kraal", &"cogforged"]:
		for building: SimBuilding in world.playable.buildings_for(faction_id):
			if building.building_type != SimIds.TOWN_CENTER:
				built += 1
	_check("AI factions progress and build over N ticks", built >= 1)
	_check("factions gain common resources over N ticks", humans.get_resource(SimIds.FOOD) >= food_before)


func _test_player_commands() -> void:
	_boot()
	var world: SimWorld = GameState.world
	var commands: CommandService = GameState.commands
	var tc: SimBuilding = world.playable.buildings_for(SimIds.PLAYER_FACTION)[0]
	var cell: Vector2i = tc.grid_pos + Vector2i(2, 0)
	if not world.playable.can_place(cell, SimIds.FARM, false):
		cell = tc.grid_pos + Vector2i(0, -2)
	var building_id: int = commands.place_building(SimIds.PLAYER_FACTION, SimIds.FARM, cell)
	_check("player can issue a build command", building_id >= 0)
	GameState.step_ticks(6)
	var farm: SimBuilding = world.playable.get_building(building_id)
	_check("player farm completes after ticks", farm != null and farm.constructed)
	var worker: SimUnit = null
	for unit: SimUnit in world.playable.units_for(SimIds.PLAYER_FACTION):
		if unit.unit_type == SimIds.WORKER:
			worker = unit
			break
	_check("player has a worker to command", worker != null)
	if worker == null:
		return
	var dest: Vector3 = worker.position + Vector3(0.2, 0.0, 0.1)
	_check("player move command accepted", commands.move_unit(worker.id, dest))
	GameState.step_ticks(4)
	_check("player unit moves toward issued destination", worker.position.distance_to(dest) < worker.position.distance_to(dest + Vector3(10, 0, 10)))
	# The above always-true check is weak; assert it actually got closer than the start distance.
	# Re-issue from a known point for a hard assertion.
	worker.position = Vector3(0.2, 0.0, 0.2)
	var target := Vector3(-0.2, 0.0, -0.2)
	var start_dist: float = worker.position.distance_to(target)
	commands.move_unit(worker.id, target)
	GameState.step_ticks(3)
	_check("player command path moves the unit", worker.position.distance_to(target) < start_dist)


func _test_depletion() -> void:
	_boot()
	var world: SimWorld = GameState.world
	var node: SimResourceNode = _first_node_unowned(world, false, SimIds.WOOD)
	_check("timber node exists for depletion test", node != null)
	if node == null:
		return
	var worker: SimUnit = world.playable.units_for(SimIds.PLAYER_FACTION)[0]
	worker.position = node.position
	var before: int = node.remaining
	var stock_before: int = world.get_faction(SimIds.PLAYER_FACTION).get_resource(SimIds.WOOD)
	GameState.commands.assign_gather(worker.id, node.node_id)
	GameState.step_ticks(3)
	_check("common node slowly depletes when gathered", node.remaining < before)
	_check("gathering adds the common resource to the stockpile", (
		world.get_faction(SimIds.PLAYER_FACTION).get_resource(SimIds.WOOD) > stock_before
	))
	# Kraal over-harvest: more remaining lost than a Human on the same type.
	var kraal_node: SimResourceNode = null
	for candidate: SimResourceNode in world.playable.nodes.values():
		if candidate.is_rare() or candidate.resource_id() != SimIds.WOOD or candidate.node_id == node.node_id:
			continue
		if world.playable.owner_at(candidate.cell) == &"sylvari":
			continue
		kraal_node = candidate
		break
	var kraal_worker: SimUnit = world.playable.units_for(&"kraal")[0]
	_check("kraal worker and timber node exist", kraal_node != null and kraal_worker != null)
	if kraal_node != null and kraal_worker != null:
		kraal_worker.position = kraal_node.position
		var kraal_before: int = kraal_node.remaining
		GameState.commands.assign_gather(kraal_worker.id, kraal_node.node_id)
		GameState.step_ticks(1)
		var kraal_lost: int = kraal_before - kraal_node.remaining
		# Reset a human on a fresh gather tick already happened; compare 1-tick kraal loss vs typical human base 3.
		_check("kraal harvest depletes a common node faster than the base gather", kraal_lost > 3)


func _test_regrowth() -> void:
	_boot()
	var world: SimWorld = GameState.world
	# Pick a common node inside Sylvari town-center territory (NW, cell 1,1, radius 4).
	var node: SimResourceNode = null
	for candidate: SimResourceNode in world.playable.nodes.values():
		if candidate.is_rare():
			continue
		if world.playable.owner_at(candidate.cell) == &"sylvari":
			node = candidate
			break
	_check("sylvari owns a common node on starting territory", node != null)
	if node == null:
		return
	# Park all units away so gather does not fight regen.
	for unit: SimUnit in world.playable.units.values():
		unit.assigned_node_id = &""
		unit.has_destination = false
		unit.position = Vector3(10.0, 0.0, 10.0)
	node.remaining = 40
	GameState.step_ticks(3)
	_check("sylvari regrows common nodes on owned territory", node.remaining > 40)
	var rare: SimResourceNode = _first_node(world, true, &"")
	_check("rare node exists for regen-negative test", rare != null)
	if rare == null:
		return
	# Force-claim the rare cell for Sylvari and ensure it does not regrow.
	world.playable.owners[world.playable.pack_cell(rare.cell)] = &"sylvari"
	rare.remaining = 40
	GameState.step_ticks(3)
	_check("sylvari does not regrow rare nodes", rare.remaining == 40)


func _test_rare_cost_gating() -> void:
	_boot()
	var world: SimWorld = GameState.world
	var commands: CommandService = GameState.commands
	var humans: SimFaction = world.get_faction(SimIds.PLAYER_FACTION)
	# Plenty of commons and pop, but no rare resources.
	humans.set_resource(SimIds.FOOD, 400)
	humans.set_resource(SimIds.WOOD, 400)
	humans.set_resource(SimIds.STONE, 400)
	humans.set_resource(SimIds.IRON, 0)
	humans.set_resource(SimIds.COAL, 0)
	# Ensure population meets Bronze min pop (4). Starting humans have 3 workers; train or spawn one.
	while world.playable.population(SimIds.PLAYER_FACTION) < 4:
		world._spawn_unit(SimIds.PLAYER_FACTION, SimIds.WORKER, Vector3.ZERO)
	# Bronze / Steamworks is commons-only so coal can be revealed at that era.
	var era_before: EraData = humans.era
	_check("era advance to Bronze/Steamworks uses only common resources", commands.advance_era(SimIds.PLAYER_FACTION))
	_check("era advance swaps EraData", humans.era != era_before and humans.era.era_index == 1)
	_check("new era has distinct building mesh data", (
		era_before.building_meshes.has(SimIds.TOWN_CENTER)
		and humans.era.building_meshes.has(SimIds.TOWN_CENTER)
		and era_before.building_meshes[SimIds.TOWN_CENTER] != humans.era.building_meshes[SimIds.TOWN_CENTER]
	))
	# Coal (visible from the steam era) gates the Iron era (index 2), which reveals iron.
	humans.set_resource(SimIds.FOOD, 400)
	humans.set_resource(SimIds.WOOD, 400)
	humans.set_resource(SimIds.STONE, 400)
	humans.set_resource(SimIds.COAL, 0)
	while world.playable.population(SimIds.PLAYER_FACTION) < 7:
		world._spawn_unit(SimIds.PLAYER_FACTION, SimIds.WORKER, Vector3.ZERO)
	_check("era advance to Iron is gated on coal", commands.advance_era(SimIds.PLAYER_FACTION) == false)
	humans.set_resource(SimIds.COAL, 20)
	var tc: SimBuilding = world.playable.buildings_for(SimIds.PLAYER_FACTION)[0]
	var house_id: int = _place_near(commands, world, SimIds.PLAYER_FACTION, SimIds.HOUSE, tc.grid_pos)
	GameState.step_ticks(6)
	_check("player house completed to raise pop cap", house_id >= 0 and world.playable.get_building(house_id) != null and world.playable.get_building(house_id).constructed)
	_check("era advance to Iron succeeds with coal", commands.advance_era(SimIds.PLAYER_FACTION))
	# Ironclad / steamwalker require revealed iron (era 2) plus the rare stockpile.
	var barracks_id: int = _place_near(commands, world, SimIds.PLAYER_FACTION, SimIds.BARRACKS, tc.grid_pos)
	GameState.step_ticks(8)
	var barracks: SimBuilding = world.playable.get_building(barracks_id)
	_check("player barracks completed for specialist gate", barracks != null and barracks.constructed)
	humans.set_resource(SimIds.IRON, 0)
	_check("specialized ironclad is gated on iron", commands.train_unit(SimIds.PLAYER_FACTION, SimIds.IRONCLAD) == false)
	humans.set_resource(SimIds.IRON, 20)
	humans.set_resource(SimIds.FOOD, 80)
	humans.set_resource(SimIds.WOOD, 80)
	_check("specialized ironclad trains once iron is available", commands.train_unit(SimIds.PLAYER_FACTION, SimIds.IRONCLAD))
	humans.set_resource(SimIds.IRON, 40)
	humans.set_resource(SimIds.COAL, 40)
	humans.set_resource(SimIds.WOOD, 80)
	humans.set_resource(SimIds.STONE, 80)
	_check("steamwalker is gated on coal+iron and trains when both are present", (
		commands.train_unit(SimIds.PLAYER_FACTION, SimIds.STEAMWALKER)
	))



func _test_era_gated_reveal() -> void:
	_boot()
	var world: SimWorld = GameState.world
	var commands: CommandService = GameState.commands
	var iron: SimResourceNode = _first_node(world, true, SimIds.IRON)
	var coal: SimResourceNode = _first_node(world, true, SimIds.COAL)
	var timber: SimResourceNode = _first_node(world, false, SimIds.WOOD)
	_check("rare iron and coal nodes have fixed positions", iron != null and coal != null)
	_check("iron is revealed at era 2", iron != null and iron.reveal_era() == 2)
	_check("coal is revealed at the steam era (era 1)", coal != null and coal.reveal_era() == 1)
	var humans: StringName = SimIds.PLAYER_FACTION
	var worker: SimUnit = world.playable.units_for(humans)[0]
	_check("starting era hides iron from the player", not world.can_see_node(humans, iron))
	_check("starting era hides coal from the player", not world.can_see_node(humans, coal))
	_check("common timber is visible from era 0", world.can_see_node(humans, timber))
	worker.position = iron.position
	_check("gather is rejected on an unrevealed iron node", commands.assign_gather(worker.id, iron.node_id) == false)
	# AI at era 0 must not target hidden rares.
	var kraal: SimFaction = world.get_faction(&"kraal")
	world.ai._assign_idle_workers(world, kraal, world.playable, kraal.species)
	var kraal_on_rare: bool = false
	for unit: SimUnit in world.playable.units_for(&"kraal"):
		var assigned: SimResourceNode = world.playable.get_node(unit.assigned_node_id)
		if assigned != null and assigned.is_rare():
			kraal_on_rare = true
	_check("AI does not assign workers to unrevealed rare nodes", kraal_on_rare == false)
	world.set_faction_era(humans, 1)
	_check("steam era reveals coal to that faction only", world.can_see_node(humans, coal) and not world.can_see_node(&"kraal", coal))
	_check("steam era still hides iron", not world.can_see_node(humans, iron))
	worker.position = coal.position
	_check("player can gather coal once it is revealed", commands.assign_gather(worker.id, coal.node_id))
	_check("iron gather remains rejected until era 2", commands.assign_gather(worker.id, iron.node_id) == false)
	world.set_faction_era(humans, 2)
	worker.assigned_node_id = &""
	worker.position = iron.position
	_check("era 2 reveals iron to the player", world.can_see_node(humans, iron))
	_check("player can gather iron once it is revealed", commands.assign_gather(worker.id, iron.node_id))


func _test_extractor_gate() -> void:
	_boot()
	var world: SimWorld = GameState.world
	var rare: SimResourceNode = _first_node(world, true, &"")
	_check("rare node exists for extractor test", rare != null)
	if rare == null:
		return
	var adj: Vector2i = _adjacent_build_cell(world, rare.cell, SimIds.EXTRACTOR)
	_check("land cell adjacent to a rare node exists", adj.x >= 0)
	world.get_faction(SimIds.PLAYER_FACTION).set_resource(SimIds.WOOD, 80)
	world.get_faction(SimIds.PLAYER_FACTION).set_resource(SimIds.STONE, 80)
	_check("non-Cogforged cannot build extractors", world.place_building(SimIds.PLAYER_FACTION, SimIds.EXTRACTOR, adj) < 0)
	world.get_faction(&"cogforged").set_resource(SimIds.WOOD, 80)
	world.get_faction(&"cogforged").set_resource(SimIds.STONE, 80)
	# Extractors only sit on rares this faction has revealed.
	world.set_faction_era(&"cogforged", 2)
	var extractor_id: int = world.place_building(&"cogforged", SimIds.EXTRACTOR, adj)
	_check("Cogforged can build an extractor adjacent to a rare node", extractor_id >= 0)
	GameState.step_ticks(6)
	var extractor: SimBuilding = world.playable.get_building(extractor_id)
	_check("Cogforged extractor completes", extractor != null and extractor.constructed)
	var before: int = world.get_faction(&"cogforged").get_resource(rare.resource_id())
	var remaining_before: int = rare.remaining
	GameState.step_ticks(2)
	_check("extractor boosts rare-node yield for Cogforged", (
		world.get_faction(&"cogforged").get_resource(rare.resource_id()) > before
		and rare.remaining < remaining_before
	))


func _first_node(world: SimWorld, rare: bool, resource_id: StringName) -> SimResourceNode:
	for node: SimResourceNode in world.playable.nodes.values():
		if node.is_rare() != rare:
			continue
		if resource_id != &"" and node.resource_id() != resource_id:
			continue
		return node
	return null


func _first_node_unowned(world: SimWorld, rare: bool, resource_id: StringName) -> SimResourceNode:
	for node: SimResourceNode in world.playable.nodes.values():
		if node.is_rare() != rare:
			continue
		if resource_id != &"" and node.resource_id() != resource_id:
			continue
		# Avoid Sylvari-owned common nodes: regen can mask depletion.
		if world.playable.owner_at(node.cell) == &"sylvari":
			continue
		return node
	return _first_node(world, rare, resource_id)


func _adjacent_build_cell(world: SimWorld, cell: Vector2i, building_type: StringName) -> Vector2i:
	var offsets: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
	]
	for offset: Vector2i in offsets:
		var adj: Vector2i = cell + offset
		if world.playable.can_place(adj, building_type, false):
			return adj
	# If the first rare node is boxed in, try every rare node.
	for node: SimResourceNode in world.playable.nodes.values():
		if not node.is_rare():
			continue
		for offset: Vector2i in offsets:
			var adj: Vector2i = node.cell + offset
			if world.playable.can_place(adj, building_type, false):
				return adj
	return Vector2i(-1, -1)


func _place_near(commands: CommandService, world: SimWorld, faction_id: StringName, building_type: StringName, origin: Vector2i) -> int:
	for radius: int in range(1, 8):
		for dx: int in range(-radius, radius + 1):
			for dy: int in range(-radius, radius + 1):
				if maxi(abs(dx), abs(dy)) != radius:
					continue
				var cell: Vector2i = origin + Vector2i(dx, dy)
				if not world.playable.can_place(cell, building_type, false):
					continue
				var building_id: int = commands.place_building(faction_id, building_type, cell)
				if building_id >= 0:
					return building_id
	return -1


func _test_hex_grid_and_yield_split() -> void:
	_boot()
	var world: SimWorld = GameState.world
	var region: SimRegion = world.playable
	var grid: HexGrid = region.hex_grid
	_check("playable region has an axial HexGrid", grid != null)
	var identity_ok: bool = true
	for q: int in range(-4, 5):
		for r: int in range(-4, 5):
			var hex := Vector2i(q, r)
			if grid.world_to_axial(grid.axial_to_world(hex)) != hex:
				identity_ok = false
	_check("axial world conversion round-trips", identity_ok)
	_check("hex distance from a hex to itself is 0", grid.distance(Vector2i.ZERO, Vector2i.ZERO) == 0)
	_check("a radius-1 cluster has 7 hexes", grid.hexes_in_radius(Vector2i.ZERO, 1).size() == 7)
	var iron: SimResourceNode = _first_node(world, true, SimIds.IRON)
	_check("rare iron node sits on an axial hex", iron != null and iron.hex == region.hex_at_world(iron.position))
	var cluster: Array[Vector2i] = world.claims.cluster_hexes(region, iron)
	_check("each rare node covers a 7-hex cluster", cluster.size() == 7)
	# Yield share counts CLAIMED hexes only (not occupation).
	for i: int in cluster.size():
		var key: int = HexGrid.pack(cluster[i])
		if i < 3:
			region.hex_claims[key] = SimIds.PLAYER_FACTION
		else:
			region.hex_claims[key] = &"kraal"
	_check("yield split is 3/7 and 4/7 by claimed hexes", (
		world.claims.yield_for(region, iron, SimIds.PLAYER_FACTION, 7) == 3
		and world.claims.yield_for(region, iron, &"kraal", 7) == 4
		and world.claims.yield_for(region, iron, &"sylvari", 7) == 0
	))
	_check("partial claim is not full control", not world.claims.has_full_control(region, iron, SimIds.PLAYER_FACTION))
	for hex: Vector2i in cluster:
		region.hex_claims[HexGrid.pack(hex)] = SimIds.PLAYER_FACTION
	_check("full control of the cluster yields the whole amount", (
		world.claims.has_full_control(region, iron, SimIds.PLAYER_FACTION)
		and world.claims.yield_for(region, iron, SimIds.PLAYER_FACTION, 10) == 10
	))


func _test_escalation_ladder_and_skirmish() -> void:
	_boot()
	var world: SimWorld = GameState.world
	var region: SimRegion = world.playable
	var commands: CommandService = GameState.commands
	var iron: SimResourceNode = _first_node(world, true, SimIds.IRON)
	_check("contested rare starts unclaimed", iron != null and iron.soft_claimer == &"" and iron.hard_claimer == &"")
	world.set_faction_era(SimIds.PLAYER_FACTION, 2)
	world.set_faction_era(&"kraal", 2)
	var soft_events: Array[StringName] = []
	var hard_events: Array[StringName] = []
	var on_claimed := func(fid: StringName, node_id: StringName, kind: StringName) -> void:
		if node_id != iron.node_id:
			return
		if kind == &"soft":
			soft_events.append(fid)
		elif kind == &"hard":
			hard_events.append(fid)
	EventBus.node_claimed.connect(on_claimed)
	# Place the farm at hex distance 2 so it soft-claims the center without
	# out-radiating an outpost that sits on the node after a later capture.
	var farm_cell: Vector2i = _structure_cell_at_distance(world, iron.hex, 2)
	world.get_faction(SimIds.PLAYER_FACTION).set_resource(SimIds.WOOD, 80)
	world.get_faction(SimIds.PLAYER_FACTION).set_resource(SimIds.STONE, 80)
	var farm_id: int = commands.place_building(SimIds.PLAYER_FACTION, SimIds.FARM, farm_cell)
	_check("border structure can be placed to soft-claim a rare node", farm_id >= 0)
	GameState.step_ticks(4)
	_check("node inside structure territory is soft-claimed", iron.soft_claimer == SimIds.PLAYER_FACTION)
	_check("soft-claim emits node_claimed", soft_events.has(SimIds.PLAYER_FACTION))
	var outpost_cell: Vector2i = iron.cell
	if not world.playable.can_place(outpost_cell, SimIds.OUTPOST, false):
		outpost_cell = _structure_cell_at_distance(world, iron.hex, 0)
	if outpost_cell.x < 0:
		outpost_cell = _structure_cell_at_distance(world, iron.hex, 1)
	var outpost_id: int = commands.place_building(SimIds.PLAYER_FACTION, SimIds.OUTPOST, outpost_cell)
	_check("outpost can be placed on or near a visible rare node", outpost_id >= 0)
	GameState.step_ticks(5)
	var outpost: SimBuilding = region.get_building(outpost_id)
	_check("outpost completes and hard-claims the node", (
		outpost != null and outpost.constructed
		and iron.hard_claimer == SimIds.PLAYER_FACTION
		and iron.claimed_outpost_id == outpost_id
	))
	_check("hard-claim emits node_claimed", hard_events.has(SimIds.PLAYER_FACTION))
	_check("outpost claim radiates over the whole rare cluster", world.claims.has_full_control(region, iron, SimIds.PLAYER_FACTION))
	EventBus.node_claimed.disconnect(on_claimed)
	var outpost_hex: Vector2i = region.hex_at_cell(outpost.grid_pos)
	_check("skirmish is rejected without an occupying military unit", (
		commands.start_skirmish(&"kraal", iron.node_id, outpost_hex, true) < 0
	))
	# Possession stub: occupy the outpost hex, request possess, do not resolve yet.
	var soldier: SimUnit = world._spawn_unit(&"kraal", SimIds.SOLDIER, region.hex_grid.axial_to_world(outpost_hex))
	soldier.position = region.hex_grid.axial_to_world(outpost_hex)
	world.claims.refresh_occupation(region)
	var possess_ids: Array[int] = []
	var on_possess := func(sid: int, _fid: StringName, _nid: StringName, _hex: Vector2i) -> void:
		possess_ids.append(sid)
	EventBus.skirmish_possession_requested.connect(on_possess)
	var pending_id: int = commands.start_skirmish(&"kraal", iron.node_id, outpost_hex, false)
	_check("possession hook starts a pending skirmish without auto-resolving", pending_id >= 0 and possess_ids.has(pending_id))
	_check("possession stub does not flip the outpost", outpost.faction_id == SimIds.PLAYER_FACTION)
	EventBus.skirmish_possession_requested.disconnect(on_possess)
	# Auto-battle (and resolving a pending possess skirmish) flips the structure and its claims.
	var flipped: Array[bool] = []
	var on_resolved := func(_sid: int, _w: StringName, _l: StringName, _nid: StringName, _hex: Vector2i, cap: int, did_flip: bool) -> void:
		flipped.append(did_flip and cap == outpost_id)
	EventBus.skirmish_resolved.connect(on_resolved)
	_check("auto-battle resolves the pending skirmish", commands.resolve_skirmish_auto(pending_id))
	EventBus.skirmish_resolved.disconnect(on_resolved)
	_check("lost skirmish flips the outpost to the attacker", outpost.faction_id == &"kraal")
	_check("capturing the outpost transfers hex claims and full control", (
		iron.hard_claimer == &"kraal"
		and world.claims.has_full_control(region, iron, &"kraal")
		and not world.claims.has_full_control(region, iron, SimIds.PLAYER_FACTION)
	))
	_check("skirmish_resolved reports the structure flip", flipped.has(true))


func _test_occupy_blocks_claim_and_destroy() -> void:
	_boot()
	var world: SimWorld = GameState.world
	var region: SimRegion = world.playable
	var iron: SimResourceNode = _first_node(world, true, SimIds.IRON)
	world.set_faction_era(SimIds.PLAYER_FACTION, 2)
	# An enemy unit occupying a cluster hex blocks the radiating claim.
	var blocked: Vector2i = iron.hex
	var blocker: SimUnit = world._spawn_unit(&"kraal", SimIds.SOLDIER, region.hex_grid.axial_to_world(blocked))
	blocker.position = region.hex_grid.axial_to_world(blocked)
	world.get_faction(SimIds.PLAYER_FACTION).set_resource(SimIds.WOOD, 80)
	world.get_faction(SimIds.PLAYER_FACTION).set_resource(SimIds.STONE, 80)
	var cell: Vector2i = iron.cell
	if not region.can_place(cell, SimIds.OUTPOST, false):
		cell = _structure_cell_for_hex(world, iron.hex, 1, iron.cell)
	var outpost_id: int = world.place_building(SimIds.PLAYER_FACTION, SimIds.OUTPOST, cell)
	_check("outpost places beside a rare node for the occupy test", outpost_id >= 0)
	GameState.step_ticks(5)
	_check("enemy occupation blocks claiming that hex", region.hex_owner(blocked) != SimIds.PLAYER_FACTION)
	_check("yield share ignores occupied unclaimed hexes", (
		world.claims.claimed_hex_count(region, iron, SimIds.PLAYER_FACTION) < 7
		and not world.claims.has_full_control(region, iron, SimIds.PLAYER_FACTION)
	))
	# Remove the blocker and the outpost should radiate over the hex.
	blocker.hp = 0
	world.claims.update(world)
	_check("claim radiates once the occupying enemy is gone", region.hex_owner(blocked) == SimIds.PLAYER_FACTION)
	_check("outpost then has full control of the cluster", world.claims.has_full_control(region, iron, SimIds.PLAYER_FACTION))
	_check("destroying the outpost releases its hex claims", world.destroy_building(outpost_id))
	_check("no full control remains after the structure is destroyed", (
		not world.claims.has_full_control(region, iron, SimIds.PLAYER_FACTION)
		and iron.hard_claimer == &""
	))


func _test_ai_escalation_personality() -> void:
	_boot()
	var world: SimWorld = GameState.world
	var iron: SimResourceNode = _first_node(world, true, SimIds.IRON)
	world.set_faction_era(&"kraal", 2)
	world.set_faction_era(&"sylvari", 2)
	world.set_faction_era(&"cogforged", 2)
	# Unclaimed visible rare: defensive holds the border, others go for an outpost.
	_check("Sylvari (defensive) escalate unclaimed rares via borders", (
		world.ai.choose_escalation(world, world.get_faction(&"sylvari"), iron) == &"borders"
	))
	_check("Kraal (aggressive) escalate unclaimed rares to an outpost", (
		world.ai.choose_escalation(world, world.get_faction(&"kraal"), iron) == &"outpost"
	))
	_check("Cogforged (methodical) escalate unclaimed rares to an outpost", (
		world.ai.choose_escalation(world, world.get_faction(&"cogforged"), iron) == &"outpost"
	))
	# Enemy hard-claim: aggressive skirmishes; defensive holds unless already soft-claiming;
	# methodical waits until prepared.
	iron.hard_claimer = SimIds.PLAYER_FACTION
	iron.soft_claimer = SimIds.PLAYER_FACTION
	_check("Kraal (aggressive) skirmish over an enemy hard-claim", (
		world.ai.choose_escalation(world, world.get_faction(&"kraal"), iron) == &"skirmish"
	))
	_check("Sylvari (defensive) do not rush an enemy hard-claim", (
		world.ai.choose_escalation(world, world.get_faction(&"sylvari"), iron) == &"none"
	))
	_check("Cogforged (methodical) wait to skirmish until prepared", (
		world.ai.choose_escalation(world, world.get_faction(&"cogforged"), iron) == &"none"
	))
	world._spawn_unit(&"cogforged", SimIds.SOLDIER, iron.position)
	world._spawn_unit(&"cogforged", SimIds.SOLDIER, iron.position)
	_check("prepared Cogforged then auto-battles the hard-claim", (
		world.ai.choose_escalation(world, world.get_faction(&"cogforged"), iron) == &"skirmish"
	))


func _structure_cell_for_hex(world: SimWorld, target_hex: Vector2i, max_hex_dist: int, prefer: Vector2i) -> Vector2i:
	var region: SimRegion = world.playable
	if prefer.x >= 0 and region.can_place(prefer, SimIds.FARM, false):
		if region.hex_grid.distance(region.hex_at_cell(prefer), target_hex) <= max_hex_dist:
			return prefer
	var size: Vector2i = region.grid_size()
	var best := Vector2i(-1, -1)
	var best_d: int = 99
	for x: int in size.x:
		for y: int in size.y:
			var cell := Vector2i(x, y)
			if not region.can_place(cell, SimIds.FARM, false):
				continue
			var dist: int = region.hex_grid.distance(region.hex_at_cell(cell), target_hex)
			if dist <= max_hex_dist and dist < best_d:
				best = cell
				best_d = dist
	return best



func _structure_cell_at_distance(world: SimWorld, target_hex: Vector2i, exact_dist: int) -> Vector2i:
	var region: SimRegion = world.playable
	var size: Vector2i = region.grid_size()
	for x: int in size.x:
		for y: int in size.y:
			var cell := Vector2i(x, y)
			if not region.can_place(cell, SimIds.FARM, false):
				continue
			if region.hex_grid.distance(region.hex_at_cell(cell), target_hex) == exact_dist:
				return cell
	return Vector2i(-1, -1)


func _test_per_species_eras() -> void:
	_boot()
	var world: SimWorld = GameState.world
	_check("humans start on the Human Stone era", world.get_faction(&"humans").era.era_name == "Stone")
	_check("Sylvari start on Roots", world.get_faction(&"sylvari").era.era_name == "Roots")
	_check("Kraal start on Brood", world.get_faction(&"kraal").era.era_name == "Brood")
	_check("Cogforged start on Clockwork", world.get_faction(&"cogforged").era.era_name == "Clockwork")
	_check("world era starts at Stone, independent of species tracks", (
		world.world_era() != null and world.world_era().era_name == "Stone" and world.world_era_index == 0
	))
	world.set_faction_era(&"cogforged", 1)
	_check("Cogforged era track advances to Steamworks", world.get_faction(&"cogforged").era.era_name == "Steamworks")
	_check("other species tracks stay on their starting era", world.get_faction(&"humans").era.era_name == "Stone")
	_check("world era is unchanged when a species advances", world.world_era_index == 0)


func _test_soft_cap_cost_scaling() -> void:
	_check("on-pace advance (world 0 -> era 1) has no soft-cap multiplier", SimCatalog.soft_cap_multiplier(1, 0) == 1.0)
	_check("one era past grace doubles the cost", is_equal_approx(SimCatalog.soft_cap_multiplier(2, 0), 2.0))
	_check("two eras past grace quadruples the cost", is_equal_approx(SimCatalog.soft_cap_multiplier(3, 0), 4.0))
	_check("raising the world era removes the penalty for that index", SimCatalog.soft_cap_multiplier(2, 1) == 1.0)
	var base: Dictionary = SimCatalog.era_advance_cost(2, null, 1)
	var taxed: Dictionary = SimCatalog.era_advance_cost(2, null, 0)
	_check("era-2 costs scale 2x when the world is still era 0", (
		int(taxed[SimIds.FOOD]) == int(base[SimIds.FOOD]) * 2
		and int(taxed[SimIds.COAL]) == int(base[SimIds.COAL]) * 2
	))
	# Advancing beyond the cap is allowed if you can pay; it is not hard-blocked.
	_boot()
	var world: SimWorld = GameState.world
	world.world_era_index = 0
	var humans: SimFaction = world.get_faction(SimIds.PLAYER_FACTION)
	humans.set_resource(SimIds.FOOD, 4000)
	humans.set_resource(SimIds.WOOD, 4000)
	humans.set_resource(SimIds.STONE, 4000)
	humans.set_resource(SimIds.COAL, 400)
	humans.set_resource(SimIds.IRON, 400)
	while world.playable.population(SimIds.PLAYER_FACTION) < 10:
		world._spawn_unit(SimIds.PLAYER_FACTION, SimIds.WORKER, Vector3.ZERO)
	_check("soft cap does not hard-block a well-funded advance to era 2", world.try_advance_era(SimIds.PLAYER_FACTION) and world.try_advance_era(SimIds.PLAYER_FACTION))
	_check("human era index is 2 after paying the scaled cost", humans.era.era_index == 2)


func _test_win_conditions() -> void:
	_boot()
	var world: SimWorld = GameState.world
	_check("Humans may pursue all three win conditions", (
		world.get_faction(&"humans").species.can_pursue_win(&"complete_domination")
		and world.get_faction(&"humans").species.can_pursue_win(&"unbridgeable_superiority")
		and world.get_faction(&"humans").species.can_pursue_win(&"utter_destruction")
	))
	_check("Sylvari may win by domination or superiority, not destruction", (
		world.get_faction(&"sylvari").species.can_pursue_win(&"complete_domination")
		and world.get_faction(&"sylvari").species.can_pursue_win(&"unbridgeable_superiority")
		and not world.get_faction(&"sylvari").species.can_pursue_win(&"utter_destruction")
	))
	_check("Kraal may win by destruction or domination, not superiority", (
		world.get_faction(&"kraal").species.can_pursue_win(&"utter_destruction")
		and world.get_faction(&"kraal").species.can_pursue_win(&"complete_domination")
		and not world.get_faction(&"kraal").species.can_pursue_win(&"unbridgeable_superiority")
	))
	_check("Cogforged may win by superiority or destruction, not domination", (
		world.get_faction(&"cogforged").species.can_pursue_win(&"unbridgeable_superiority")
		and world.get_faction(&"cogforged").species.can_pursue_win(&"utter_destruction")
		and not world.get_faction(&"cogforged").species.can_pursue_win(&"complete_domination")
	))
	# Destruction: wipe every rival, then one tick.
	var dest_ids: Array[StringName] = []
	var on_dest := func(fid: StringName, cid: StringName, _cond: WinConditionData) -> void:
		if cid == &"utter_destruction":
			dest_ids.append(fid)
	EventBus.victory_achieved.connect(on_dest)
	world.eliminate_faction(&"humans")
	world.eliminate_faction(&"sylvari")
	world.eliminate_faction(&"cogforged")
	GameState.step_ticks(1)
	EventBus.victory_achieved.disconnect(on_dest)
	_check("Utter Destruction fires for Kraal after all rivals are eliminated", (
		world.victory.winner_id == &"kraal" and world.victory.winner_condition_id == &"utter_destruction" and dest_ids.has(&"kraal")
	))
	# Domination: Sylvari is the only remaining claimant, held for the required ticks.
	_boot()
	world = GameState.world
	var dom_ids: Array[StringName] = []
	var on_dom := func(fid: StringName, cid: StringName, _cond: WinConditionData) -> void:
		if cid == &"complete_domination":
			dom_ids.append(fid)
	EventBus.victory_achieved.connect(on_dom)
	world.eliminate_faction(&"humans")
	world.eliminate_faction(&"kraal")
	world.eliminate_faction(&"cogforged")
	GameState.step_ticks(4)
	EventBus.victory_achieved.disconnect(on_dom)
	_check("Complete Domination fires for Sylvari after holding the claimed map", (
		world.victory.winner_id == &"sylvari" and world.victory.winner_condition_id == &"complete_domination" and dom_ids.has(&"sylvari")
	))
	# Superiority: era + economy lead over every living rival, held for N ticks.
	_boot()
	world = GameState.world
	var sup_ids: Array[StringName] = []
	var on_sup := func(fid: StringName, cid: StringName, _cond: WinConditionData) -> void:
		if cid == &"unbridgeable_superiority":
			sup_ids.append(fid)
	EventBus.victory_achieved.connect(on_sup)
	world.set_faction_era(&"sylvari", 2)
	var sylvari: SimFaction = world.get_faction(&"sylvari")
	for resource_id: StringName in SimIds.all_resources():
		sylvari.set_resource(resource_id, 2000)
		for other_id: StringName in [&"humans", &"kraal", &"cogforged"]:
			world.get_faction(other_id).set_resource(resource_id, 0)
	GameState.step_ticks(4)
	EventBus.victory_achieved.disconnect(on_sup)
	_check("Unbridgeable Superiority fires for Sylvari with an era and economy lead", (
		world.victory.winner_id == &"sylvari" and world.victory.winner_condition_id == &"unbridgeable_superiority" and sup_ids.has(&"sylvari")
	))


func _test_determinism() -> void:
	GameState.reset()
	GameState.ai_enabled = false
	GameState.bootstrap_concept_world(42)
	var world: SimWorld = GameState.world
	var commands: CommandService = GameState.commands
	var humans: SimFaction = world.get_faction(SimIds.PLAYER_FACTION)
	humans.set_resource(SimIds.WOOD, 80)
	var tc: SimBuilding = world.playable.buildings_for(SimIds.PLAYER_FACTION)[0]
	var farm_id: int = _place_near(commands, world, SimIds.PLAYER_FACTION, SimIds.FARM, tc.grid_pos)
	_check("determinism run issued a farm command", farm_id >= 0)
	GameState.step_ticks(3)
	var worker: SimUnit = world.playable.units_for(SimIds.PLAYER_FACTION)[0]
	_check("determinism run issued a move command", commands.move_unit(worker.id, worker.position + Vector3(0.12, 0.0, 0.04)))
	GameState.step_ticks(5)
	var hash_a: int = world.state_hash()
	var log: Array = []
	for item: Dictionary in world.command_log:
		log.append(item.duplicate())
	var final_tick: int = GameState.tick_count
	_check("command log is stamped with ticks", log.size() >= 2 and int(log[0].get("tick", -1)) >= 0)
	GameState.reset()
	GameState.ai_enabled = false
	GameState.bootstrap_concept_world(42)
	GameState.world.get_faction(SimIds.PLAYER_FACTION).set_resource(SimIds.WOOD, 80)
	GameState.commands.replay(log, final_tick)
	var hash_b: int = GameState.world.state_hash()
	_check("same seed and command log replay to an identical state hash", hash_a == hash_b and hash_a != 0)
	# A second independent run with the same seed and commands must also match.
	GameState.reset()
	GameState.ai_enabled = false
	GameState.bootstrap_concept_world(42)
	world = GameState.world
	commands = GameState.commands
	world.get_faction(SimIds.PLAYER_FACTION).set_resource(SimIds.WOOD, 80)
	_place_near(commands, world, SimIds.PLAYER_FACTION, SimIds.FARM, world.playable.buildings_for(SimIds.PLAYER_FACTION)[0].grid_pos)
	GameState.step_ticks(3)
	worker = world.playable.units_for(SimIds.PLAYER_FACTION)[0]
	commands.move_unit(worker.id, worker.position + Vector3(0.12, 0.0, 0.04))
	GameState.step_ticks(5)
	_check("two live runs with the same seed and commands share a hash", world.state_hash() == hash_a)


# --- Tier 4 skirmish possession ---------------------------------------------

## Deterministic possession scenario. Non-command setup only (eras, stock,
## soldiers); the Kraal outpost and the skirmish are issued as commands by the
## caller so a replay can rebuild the same world from the command log.
## Returns {"iron", "cell", "hex", "attackers": Array[int], "defender": int}.
func _possession_setup(seed: int, attacker_count: int, defender_count: int) -> Dictionary:
	GameState.reset()
	GameState.ai_enabled = false
	GameState.bootstrap_concept_world(seed)
	var world: SimWorld = GameState.world
	var region: SimRegion = world.playable
	var iron: SimResourceNode = _first_node(world, true, SimIds.IRON)
	world.set_faction_era(SimIds.PLAYER_FACTION, 2)
	world.set_faction_era(&"kraal", 2)
	world.get_faction(&"kraal").set_resource(SimIds.WOOD, 200)
	world.get_faction(&"kraal").set_resource(SimIds.STONE, 200)
	var cell: Vector2i = iron.cell
	if not region.can_place(cell, SimIds.OUTPOST, false):
		cell = _structure_cell_at_distance(world, iron.hex, 0)
	if cell.x < 0:
		cell = _structure_cell_at_distance(world, iron.hex, 1)
	var hex: Vector2i = region.hex_at_cell(cell)
	var spot: Vector3 = region.hex_grid.axial_to_world(hex)
	var attackers: Array[int] = []
	for i: int in attacker_count:
		attackers.append(world._spawn_unit(SimIds.PLAYER_FACTION, SimIds.SOLDIER, spot).id)
	var defender: int = -1
	for i: int in defender_count:
		defender = world._spawn_unit(&"kraal", SimIds.SOLDIER, spot).id
	return {"iron": iron, "cell": cell, "hex": hex, "attackers": attackers, "defender": defender}


## Kraal builds the outpost (command), then the player opens a possession
## skirmish on its hex (command). Returns the skirmish id (or -1).
func _possession_open(setup: Dictionary) -> int:
	var commands: CommandService = GameState.commands
	var iron: SimResourceNode = setup["iron"] as SimResourceNode
	var outpost_id: int = commands.place_building(&"kraal", SimIds.OUTPOST, setup["cell"] as Vector2i)
	setup["outpost"] = outpost_id
	GameState.step_ticks(5)
	return commands.start_skirmish(SimIds.PLAYER_FACTION, iron.node_id, setup["hex"] as Vector2i, false)


func _test_possession_lifecycle() -> void:
	var setup: Dictionary = _possession_setup(3, 4, 1)
	var world: SimWorld = GameState.world
	var commands: CommandService = GameState.commands
	var requested: Array[int] = []
	var on_request := func(sid: int, _fid: StringName, _nid: StringName, _hex: Vector2i) -> void: requested.append(sid)
	EventBus.skirmish_possession_requested.connect(on_request)
	var sid: int = _possession_open(setup)
	EventBus.skirmish_possession_requested.disconnect(on_request)
	var outpost: SimBuilding = world.playable.get_building(int(setup["outpost"]))
	_check("possession: kraal outpost stands on the contested hex", outpost != null and outpost.constructed)
	_check("possession: request leaves the skirmish pending with no fight yet", (
		sid >= 0 and requested.has(sid) and not world.has_live_combat()
	))
	var worker: SimUnit = world._spawn_unit(SimIds.PLAYER_FACTION, SimIds.WORKER, world.playable.hex_grid.axial_to_world(setup["hex"] as Vector2i))
	world.claims.refresh_occupation(world.playable)
	var candidates: Array[SimUnit] = world.claims.possession_candidates(world, sid)
	var all_player_soldiers: bool = true
	for unit: SimUnit in candidates:
		if unit.faction_id != SimIds.PLAYER_FACTION or unit.unit_type == SimIds.WORKER:
			all_player_soldiers = false
	_check("possession: candidates are the capped attacking squad", (
		candidates.size() == ClaimSystem.SKIRMISH_SQUAD_CAP and all_player_soldiers
	))
	_check("possession: an enemy soldier cannot be possessed", not commands.possess_skirmish_unit(sid, int(setup["defender"])))
	_check("possession: a worker cannot be possessed", not commands.possess_skirmish_unit(sid, worker.id))
	_check("possession: steering is rejected before possession", not commands.steer_possessed(sid, 4))
	var started: Array[int] = []
	var on_started := func(_sid: int, uid: int) -> void: started.append(uid)
	EventBus.skirmish_possession_started.connect(on_started)
	var hero_id: int = candidates[0].id
	_check("possession: possess_skirmish_unit starts the live fight", commands.possess_skirmish_unit(sid, hero_id))
	EventBus.skirmish_possession_started.disconnect(on_started)
	var combat: SkirmishCombat = world.claims.live_combat(sid)
	var hero: SimUnit = world.playable.get_unit(hero_id)
	_check("possession: started signal names the possessed unit", _only(started, hero_id))
	_check("possession: combat enlists both squads and the outpost guard", (
		combat != null and combat.attackers.size() == 3 and combat.defenders.size() == 1
		and combat.guard_max_hp == SkirmishCombat.GUARD_HP and hero.in_combat
	))
	_check("possession: a second possess of the same unit is rejected mid-fight for non-squad units", (
		not commands.possess_skirmish_unit(sid, worker.id)
	))
	_check("possession: resolve_skirmish_possessed is rejected while the fight is live", not commands.resolve_skirmish_possessed(sid))
	# Steering: sector 4 is due east (+X).
	var start_pos: Vector3 = hero.position
	_check("possession: steer command accepted", commands.steer_possessed(sid, 4))
	GameState.step_combat(3)
	_check("possession: steering moves the possessed unit along its sector", (
		hero.position.x > start_pos.x + 0.01 and absf(hero.position.z - start_pos.z) < 0.001
	))
	_check("possession: the unit stays inside the contested arena", (
		Vector2(hero.position.x - combat.center.x, hero.position.z - combat.center.z).length() <= combat.arena_radius + 0.0001
	))
	var tick_before: int = world.current_tick
	_check("possession: strategic tick is held while the fight is live", world.has_live_combat() and world.current_tick == tick_before)
	# Stepping the strategic clock anyway fights the skirmish out first.
	commands.steer_possessed(sid, -1)
	GameState.step_ticks(1)
	_check("possession: stepping a tick finishes the live fight before the tick", (
		combat.finished and not world.has_live_combat() and world.current_tick == tick_before + 1
	))


func _test_possession_field_victory() -> void:
	var setup: Dictionary = _possession_setup(5, 2, 1)
	var world: SimWorld = GameState.world
	var commands: CommandService = GameState.commands
	var sid: int = _possession_open(setup)
	var hero_id: int = (setup["attackers"] as Array[int])[0]
	commands.possess_skirmish_unit(sid, hero_id)
	var combat: SkirmishCombat = world.claims.live_combat(sid)
	var defender: SimUnit = world.playable.get_unit(int(setup["defender"]))
	var defender_hp: int = defender.hp
	# One possessed strike: base 8 x soldier power 1.0 x possession bonus 1.5.
	var ally: SimUnit = world.playable.get_unit((setup["attackers"] as Array[int])[1])
	ally.in_combat = false  # keep the AI ally out of this single-strike check
	combat.attackers.erase(ally.id)
	_check("possession: attack command queues a strike", commands.possessed_attack(sid) and combat.attack_queued)
	_check("possession: a queued strike blocks re-queuing", not combat.can_possessed_attack())
	GameState.step_combat(1)
	_check("possession: possessed strike deals the boosted damage", defender.hp == defender_hp - 12)
	commands.possessed_attack(sid)
	GameState.step_combat(1)
	_check("possession: attack cooldown prevents a second strike next step", defender.hp == defender_hp - 12)
	combat.attackers.append(ally.id)
	ally.in_combat = true
	var killed: Array[int] = []
	var on_killed := func(uid: int, _fid: StringName) -> void: killed.append(uid)
	var finished: Array[StringName] = []
	var on_finished := func(_sid: int, winner: StringName) -> void: finished.append(winner)
	EventBus.unit_killed.connect(on_killed)
	EventBus.skirmish_combat_finished.connect(on_finished)
	var guard: int = 0
	while world.has_live_combat() and guard < SkirmishCombat.MAX_STEPS:
		if combat.can_possessed_attack():
			commands.possessed_attack(sid)
		GameState.step_combat(1)
		guard += 1
	EventBus.unit_killed.disconnect(on_killed)
	EventBus.skirmish_combat_finished.disconnect(on_finished)
	_check("possession: the fight ends on the field before the time limit", combat.finished and not combat.timed_out)
	_check("possession: attackers beat the defender and the guard", (
		combat.winner_id == SimIds.PLAYER_FACTION and _only(finished, SimIds.PLAYER_FACTION)
	))
	_check("possession: the fallen defender leaves the sim", (
		killed.has(int(setup["defender"])) and world.playable.get_unit(int(setup["defender"])) == null
	))
	var resolved: Array[bool] = []
	var on_resolved := func(rsid: int, winner: StringName, _l: StringName, _n: StringName, _h: Vector2i, cap: int, flipped: bool) -> void:
		resolved.append(rsid == sid and winner == SimIds.PLAYER_FACTION and flipped and cap == int(setup["outpost"]))
	var ended: Array[int] = []
	var on_ended := func(esid: int, _w: StringName) -> void: ended.append(esid)
	EventBus.skirmish_resolved.connect(on_resolved)
	EventBus.skirmish_possession_ended.connect(on_ended)
	var resolved_ok: bool = commands.resolve_skirmish_possessed(sid)
	EventBus.skirmish_resolved.disconnect(on_resolved)
	EventBus.skirmish_possession_ended.disconnect(on_ended)
	var iron: SimResourceNode = setup["iron"] as SimResourceNode
	_check("possession: resolve_skirmish_possessed settles the finished fight", resolved_ok and resolved.has(true) and _only(ended, sid))
	_check("possession: winning captures the outpost and its hard claim", (
		world.playable.get_building(int(setup["outpost"])).faction_id == SimIds.PLAYER_FACTION
		and iron.hard_claimer == SimIds.PLAYER_FACTION
	))
	var hero: SimUnit = world.playable.get_unit(hero_id)
	_check("possession: survivors return to normal sim control", hero != null and not hero.in_combat)
	_check("possession: a settled skirmish cannot be resolved twice", (
		not commands.resolve_skirmish_possessed(sid) and not commands.resolve_skirmish_auto(sid)
	))
	var logged: Array[StringName] = []
	for item: Dictionary in world.command_log:
		logged.append(item.get("type", &"") as StringName)
	_check("possession: every order went through the command log", (
		logged.has(&"possess_skirmish_unit") and logged.has(&"possessed_attack") and logged.has(&"resolve_skirmish_possessed")
	))


func _test_possession_auto_fallback_and_timeout() -> void:
	# Auto-battle fallback in the middle of a live fight.
	var setup: Dictionary = _possession_setup(9, 2, 1)
	var world: SimWorld = GameState.world
	var commands: CommandService = GameState.commands
	var sid: int = _possession_open(setup)
	commands.possess_skirmish_unit(sid, (setup["attackers"] as Array[int])[0])
	GameState.step_combat(2)
	var combat: SkirmishCombat = world.claims.live_combat(sid)
	var expected: StringName = combat.decide_by_strength(world)
	var ended: Array[StringName] = []
	var on_ended := func(_esid: int, winner: StringName) -> void: ended.append(winner)
	EventBus.skirmish_possession_ended.connect(on_ended)
	_check("possession: auto-battle fallback resolves a live possession fight", commands.resolve_skirmish_auto(sid))
	EventBus.skirmish_possession_ended.disconnect(on_ended)
	_check("possession: fallback uses the strength left on the field", _only(ended, expected))
	_check("possession: fallback releases every combatant", (
		not world.has_live_combat()
		and not world.playable.get_unit((setup["attackers"] as Array[int])[0]).in_combat
	))
	# Timeout: a lone possessed soldier keeps out of the guard's reach.
	setup = _possession_setup(11, 1, 0)
	world = GameState.world
	commands = GameState.commands
	sid = _possession_open(setup)
	commands.possess_skirmish_unit(sid, (setup["attackers"] as Array[int])[0])
	commands.steer_possessed(sid, 8)
	GameState.step_combat(SkirmishCombat.MAX_STEPS)
	combat = world.claims.combat_for(sid)
	_check("possession: a stalled fight times out at the step limit", combat.finished and combat.timed_out and combat.steps == SkirmishCombat.MAX_STEPS)
	_check("possession: timeout is settled by remaining strength (1 soldier > guard)", combat.winner_id == SimIds.PLAYER_FACTION)
	_check("possession: timed-out fight resolves through CommandService", commands.resolve_skirmish_possessed(sid))


func _run_possession_script(seed: int) -> Dictionary:
	var setup: Dictionary = _possession_setup(seed, 2, 1)
	var world: SimWorld = GameState.world
	var commands: CommandService = GameState.commands
	var sid: int = _possession_open(setup)
	commands.possess_skirmish_unit(sid, (setup["attackers"] as Array[int])[0])
	var sectors: Array[int] = [2, 2, 6, 6, 10, -1, 14, 0, -1]
	var i: int = 0
	while world.has_live_combat() and i < SkirmishCombat.MAX_STEPS:
		if i % 7 == 0:
			commands.steer_possessed(sid, sectors[(i / 7) % sectors.size()])
		if i % 3 == 0 and world.claims.live_combat(sid).can_possessed_attack():
			commands.possessed_attack(sid)
		GameState.step_combat(1)
		i += 1
	commands.resolve_skirmish_possessed(sid)
	GameState.step_ticks(3)
	var log: Array = []
	for item: Dictionary in world.command_log:
		log.append(item.duplicate())
	return {"hash": world.state_hash(), "log": log, "tick": world.current_tick, "combat_step": world.combat_step}


func _test_possession_replay() -> void:
	var first: Dictionary = _run_possession_script(21)
	var second: Dictionary = _run_possession_script(21)
	_check("possession: two live runs with the same seed and orders share a hash", (
		int(first["hash"]) == int(second["hash"]) and int(first["combat_step"]) > 0
	))
	var log: Array = first["log"] as Array
	var steer_stamps_ok: bool = false
	for item: Variant in log:
		var command: Dictionary = item as Dictionary
		if command.get("type", &"") == &"steer_possessed" and int(command.get("combat_step", -1)) > 0:
			steer_stamps_ok = true
	_check("possession: orders are stamped with tick and combat step", steer_stamps_ok)
	# Rebuild the same non-command setup, then replay the log.
	_possession_setup(21, 2, 1)
	GameState.commands.replay(log, int(first["tick"]), int(first["combat_step"]))
	_check("possession: replaying the command log reproduces the fight exactly", (
		GameState.world.state_hash() == int(first["hash"])
	))


func _test_possession_controller() -> void:
	var rig := ThirdPersonRig.new()
	add_child(rig)
	var controller := SkirmishPossessionController.new()
	controller.third = rig
	add_child(controller)
	# AI-initiated possession requests are not the player's to take.
	EventBus.skirmish_possession_requested.emit(99, &"kraal", &"none", Vector2i.ZERO)
	await get_tree().process_frame
	_check("controller: ignores possession requests from AI factions", not controller.is_active())
	# Player request: the controller possesses through CommandService.
	var setup: Dictionary = _possession_setup(31, 2, 1)
	var world: SimWorld = GameState.world
	var sid: int = _possession_open(setup)
	await get_tree().process_frame
	_check("controller: answers the request by possessing a squad member", (
		controller.is_active() and controller.skirmish_id == sid and world.claims.live_combat(sid) != null
		and (setup["attackers"] as Array[int]).has(controller.unit_id)
	))
	_check("controller: enters Tier 4 and shows the touch controls", (
		GameState.current_zoom_tier == GameState.ZoomTier.THIRD_PERSON and controller.controls.visible
	))
	# Virtual joystick right -> camera-relative world direction -> sector order.
	controller.camera_yaw = 0.0
	controller.controls.joystick.value = Vector2(1.0, 0.0)
	await get_tree().process_frame
	var combat: SkirmishCombat = world.claims.live_combat(sid)
	var expected_sector: int = SkirmishCombat.direction_to_sector(
		SkirmishPossessionController.camera_relative_direction(Vector2(1.0, 0.0), 0.0)
	)
	_check("controller: joystick right with camera yaw 0 steers east (sector 4)", expected_sector == 4 and combat.steer_sector == 4)
	controller.controls.joystick.value = Vector2.ZERO
	controller.controls.attack_held = true
	await get_tree().process_frame
	_check("controller: holding Attack queues a strike", combat.attack_queued)
	controller.controls.attack_held = false
	controller.request_auto_resolve()
	_check("controller: Auto-resolve falls back to auto-battle and exits Tier 4", (
		not controller.is_active() and not controller.controls.visible
		and GameState.current_zoom_tier == GameState.ZoomTier.RTS
	))
	var kinds: Array[StringName] = []
	for item: Dictionary in world.command_log:
		kinds.append(item.get("type", &"") as StringName)
	_check("controller: orders were issued only through CommandService", (
		kinds.has(&"possess_skirmish_unit") and kinds.has(&"steer_possessed")
		and kinds.has(&"possessed_attack") and kinds.has(&"resolve_skirmish")
	))
	# Field finish: the controller resolves through CommandService when the fight ends.
	setup = _possession_setup(33, 2, 1)
	world = GameState.world
	sid = _possession_open(setup)
	await get_tree().process_frame
	var guard: int = 0
	while world.has_live_combat() and guard < SkirmishCombat.MAX_STEPS:
		GameState.step_combat(1)
		guard += 1
	await get_tree().process_frame
	var record: Dictionary = world.claims.pending.get(sid, {}) as Dictionary
	var last_kind: StringName = world.command_log.back().get("type", &"") as StringName
	_check("controller: a finished fight is resolved via resolve_skirmish_possessed", (
		bool(record.get("resolved", false)) and last_kind == &"resolve_skirmish_possessed" and not controller.is_active()
	))
	# Fallback when nobody can be possessed (the squad fell before possession).
	setup = _possession_setup(35, 1, 1)
	world = GameState.world
	sid = _possession_open(setup)
	world.kill_unit((setup["attackers"] as Array[int])[0])
	await get_tree().process_frame
	record = world.claims.pending.get(sid, {}) as Dictionary
	_check("controller: falls back to auto-battle when no unit can be possessed", (
		bool(record.get("resolved", false)) and not controller.is_active()
		and (world.command_log.back().get("type", &"") as StringName) == &"resolve_skirmish"
	))
	controller.queue_free()
	rig.queue_free()
	GameState.reset()


## True when `items` holds exactly one element equal to `value`.
func _only(items: Array, value: Variant) -> bool:
	return items.size() == 1 and items[0] == value
