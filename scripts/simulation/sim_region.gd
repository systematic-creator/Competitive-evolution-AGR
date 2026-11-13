class_name SimRegion
extends RefCounted
## One region's grid, tiles, buildings, units, resource nodes, and territory.

var data: RegionData
var tiles: PackedInt32Array = PackedInt32Array()
## cell packed as x * 1000 + y -> faction_id
var owners: Dictionary = {}
## cell packed -> consecutive hold ticks for the current owner
var hold_ticks: Dictionary = {}
var buildings: Dictionary = {}
var units: Dictionary = {}
var nodes: Dictionary = {}
var next_id: int = 1


func region_id() -> StringName:
	return data.region_id


func grid_size() -> Vector2i:
	return data.grid_size


func cell_size() -> float:
	return data.cell_size


func is_cell_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < data.grid_size.x and cell.y < data.grid_size.y


func _index(cell: Vector2i) -> int:
	return cell.x + cell.y * data.grid_size.x


func pack_cell(cell: Vector2i) -> int:
	return cell.x * 1000 + cell.y


func tile_at(cell: Vector2i) -> int:
	if not is_cell_in_bounds(cell):
		return SimIds.TILE_LAND
	return tiles[_index(cell)]


func set_tile(cell: Vector2i, tile: int) -> void:
	if is_cell_in_bounds(cell):
		tiles[_index(cell)] = tile


func is_water(cell: Vector2i) -> bool:
	return tile_at(cell) == SimIds.TILE_WATER


func is_coast(cell: Vector2i) -> bool:
	return tile_at(cell) == SimIds.TILE_COAST


func is_water_adjacent(cell: Vector2i) -> bool:
	var t: int = tile_at(cell)
	return t == SimIds.TILE_WATER or t == SimIds.TILE_COAST


func owner_at(cell: Vector2i) -> StringName:
	return owners.get(pack_cell(cell), &"") as StringName


func hold_ticks_at(cell: Vector2i) -> int:
	return int(hold_ticks.get(pack_cell(cell), 0))


func defense_multiplier(cell: Vector2i, species: SpeciesData) -> float:
	if species == null:
		return 1.0
	var bonus: float = float(hold_ticks_at(cell)) * species.defense_hold_bonus_per_tick
	return 1.0 + minf(species.max_hold_defense_bonus, bonus)


func cell_to_world(cell: Vector2i) -> Vector3:
	var origin := Vector3(
		-float(data.grid_size.x) * data.cell_size * 0.5,
		0.0,
		-float(data.grid_size.y) * data.cell_size * 0.5
	)
	return origin + Vector3((float(cell.x) + 0.5) * data.cell_size, 0.0, (float(cell.y) + 0.5) * data.cell_size)


func world_to_cell(pos: Vector3) -> Vector2i:
	var origin_x: float = -float(data.grid_size.x) * data.cell_size * 0.5
	var origin_z: float = -float(data.grid_size.y) * data.cell_size * 0.5
	var x: int = clampi(int(floor((pos.x - origin_x) / data.cell_size)), 0, data.grid_size.x - 1)
	var y: int = clampi(int(floor((pos.z - origin_z) / data.cell_size)), 0, data.grid_size.y - 1)
	return Vector2i(x, y)


func is_occupied(cell: Vector2i) -> bool:
	for building: SimBuilding in buildings.values():
		if building.grid_pos == cell:
			return true
	return false


func can_place(cell: Vector2i, building_type: StringName, prefer_water: bool) -> bool:
	if not is_cell_in_bounds(cell) or is_occupied(cell):
		return false
	if is_water(cell):
		return false
	# prefer_water stays available for future coastal site scoring; all land buildings are legal.
	return true


func alloc_id() -> int:
	var id: int = next_id
	next_id += 1
	return id


func add_building(building: SimBuilding) -> void:
	buildings[building.id] = building


func add_unit(unit: SimUnit) -> void:
	units[unit.id] = unit


func add_node(node: SimResourceNode) -> void:
	nodes[node.node_id] = node


func get_building(building_id: int) -> SimBuilding:
	return buildings.get(building_id) as SimBuilding


func get_unit(unit_id: int) -> SimUnit:
	return units.get(unit_id) as SimUnit


func get_node(node_id: StringName) -> SimResourceNode:
	return nodes.get(node_id) as SimResourceNode


func buildings_for(faction_id: StringName) -> Array[SimBuilding]:
	var out: Array[SimBuilding] = []
	for building: SimBuilding in buildings.values():
		if building.faction_id == faction_id:
			out.append(building)
	return out


func units_for(faction_id: StringName) -> Array[SimUnit]:
	var out: Array[SimUnit] = []
	for unit: SimUnit in units.values():
		if unit.faction_id == faction_id:
			out.append(unit)
	return out


func completed_count(faction_id: StringName, building_type: StringName) -> int:
	var n: int = 0
	for building: SimBuilding in buildings_for(faction_id):
		if building.constructed and building.building_type == building_type:
			n += 1
	return n


func population(faction_id: StringName) -> int:
	return units_for(faction_id).size()


func population_cap(faction_id: StringName) -> int:
	var cap: int = 0
	for building: SimBuilding in buildings_for(faction_id):
		if building.constructed:
			cap += SimCatalog.building_pop_cap(building.building_type)
	return cap


func setup_tiles() -> void:
	tiles.resize(data.grid_size.x * data.grid_size.y)
	tiles.fill(SimIds.TILE_LAND)
	# Deterministic river running west -> east through the southern mid-belt.
	for x: int in data.grid_size.x:
		var y: int = 9 + int(round(sin(float(x) * 0.55) * 1.4))
		for dy: int in range(-1, 2):
			var cell := Vector2i(x, y + dy)
			if is_cell_in_bounds(cell):
				set_tile(cell, SimIds.TILE_WATER)
	# Coast = land orthogonally adjacent to water.
	for x: int in data.grid_size.x:
		for y: int in data.grid_size.y:
			var cell := Vector2i(x, y)
			if tile_at(cell) != SimIds.TILE_LAND:
				continue
			var water_near: bool = false
			for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if is_water(cell + offset):
					water_near = true
					break
			if water_near:
				set_tile(cell, SimIds.TILE_COAST)


func refresh_territory() -> void:
	var claims: Dictionary = {}
	for building: SimBuilding in buildings.values():
		if not building.constructed:
			continue
		var radius: int = 4 if building.building_type == SimIds.TOWN_CENTER else (1 if building.building_type == SimIds.HOUSE else 2)
		for dx: int in range(-radius, radius + 1):
			for dy: int in range(-radius, radius + 1):
				if abs(dx) + abs(dy) > radius:
					continue
				var cell: Vector2i = building.grid_pos + Vector2i(dx, dy)
				if not is_cell_in_bounds(cell):
					continue
				var key: int = pack_cell(cell)
				var dist: int = abs(dx) + abs(dy)
				if not claims.has(key) or dist < int(claims[key]["dist"]):
					claims[key] = {"faction": building.faction_id, "dist": dist}
	var next_owners: Dictionary = {}
	for key: int in claims:
		next_owners[key] = claims[key]["faction"]
	# Hold-time: increment if the same owner kept the cell, otherwise reset.
	var next_holds: Dictionary = {}
	for key: int in next_owners:
		var fid: StringName = next_owners[key] as StringName
		if owners.get(key, &"") == fid:
			next_holds[key] = int(hold_ticks.get(key, 0)) + 1
		else:
			next_holds[key] = 1
	owners = next_owners
	hold_ticks = next_holds
