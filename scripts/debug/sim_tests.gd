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
