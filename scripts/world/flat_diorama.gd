class_name FlatDiorama
extends Node3D
## Playable region: terrain, water, resource nodes, buildings, units, nav mesh.

var grid: BuildGrid
var _entities: Node3D
var _nodes_root: Node3D
var _nav: NavigationRegion3D
var _built: bool = false


func _ready() -> void:
	_nav = NavigationRegion3D.new()
	add_child(_nav)
	_entities = Node3D.new()
	_entities.name = "Entities"
	add_child(_entities)
	_nodes_root = Node3D.new()
	_nodes_root.name = "ResourceNodes"
	add_child(_nodes_root)
	grid = BuildGrid.new()
	grid.name = "BuildGrid"
	add_child(grid)
	grid.visible = false
	var hex_overlay := HexOverlay.new()
	hex_overlay.name = "HexOverlay"
	add_child(hex_overlay)
	EventBus.world_bootstrapped.connect(_rebuild)
	EventBus.building_placed.connect(_on_building_placed)
	EventBus.unit_spawned.connect(_on_unit_spawned)
	EventBus.zoom_tier_changed.connect(_on_tier)
	EventBus.era_changed.connect(_on_era_changed)
	if GameState.world != null:
		_rebuild()


func _rebuild(_a: Variant = null, _b: Variant = null, _c: Variant = null, _d: Variant = null) -> void:
	if GameState.world == null:
		return
	_built = true
	_build_terrain(GameState.world.playable)
	_spawn_all()
	grid.rebuild(GameState.world.playable)
	_on_tier(int(GameState.current_zoom_tier), int(GameState.current_zoom_tier))


func _build_terrain(region: SimRegion) -> void:
	for child in _nav.get_children():
		child.queue_free()
	var size: Vector2i = region.grid_size()
	var cell: float = region.cell_size()
	for x: int in size.x:
		for y: int in size.y:
			var tile: int = region.tile_at(Vector2i(x, y))
			var instance := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(cell * 0.98, 0.01 if tile != SimIds.TILE_WATER else 0.006, cell * 0.98)
			var material := StandardMaterial3D.new()
			match tile:
				SimIds.TILE_WATER:
					material.albedo_color = Color(0.15, 0.4, 0.65)
				SimIds.TILE_COAST:
					material.albedo_color = Color(0.76, 0.7, 0.42)
				_:
					material.albedo_color = Color(0.28, 0.48, 0.26)
			mesh.material = material
			instance.mesh = mesh
			instance.position = region.cell_to_world(Vector2i(x, y))
			instance.position.y = -0.004 if tile == SimIds.TILE_WATER else 0.0
			_nav.add_child(instance)
	var extent: float = float(size.x) * cell * 0.5
	var src := NavigationMeshSourceGeometryData3D.new()
	var faces := PackedVector3Array([
		Vector3(-extent, 0.0, -extent), Vector3(extent, 0.0, -extent), Vector3(extent, 0.0, extent),
		Vector3(-extent, 0.0, -extent), Vector3(extent, 0.0, extent), Vector3(-extent, 0.0, extent),
	])
	src.add_faces(faces, Transform3D.IDENTITY)
	var nav_mesh := NavigationMesh.new()
	nav_mesh.cell_size = 0.05
	nav_mesh.cell_height = 0.05
	nav_mesh.agent_radius = 0.015
	nav_mesh.agent_height = 0.05
	nav_mesh.agent_max_climb = 0.05
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, src)
	if is_inside_tree():
		var map_rid: RID = get_world_3d().navigation_map
		NavigationServer3D.map_set_cell_size(map_rid, 0.05)
		NavigationServer3D.map_set_cell_height(map_rid, 0.05)
	_nav.navigation_mesh = nav_mesh
	var floor_body := StaticBody3D.new()
	var floor_col := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	# extent already computed above
	floor_shape.size = Vector3(extent * 2.0, 0.02, extent * 2.0)
	floor_col.shape = floor_shape
	floor_col.position = Vector3(0.0, -0.01, 0.0)
	floor_body.add_child(floor_col)
	_nav.add_child(floor_body)


func _spawn_all() -> void:
	for child in _entities.get_children():
		child.queue_free()
	for child in _nodes_root.get_children():
		child.queue_free()
	var world: SimWorld = GameState.world
	for building: SimBuilding in world.playable.buildings.values():
		_add_building(building)
	for unit: SimUnit in world.playable.units.values():
		_add_unit(unit)
	for node: SimResourceNode in world.playable.nodes.values():
		_add_node_marker(node)


func _add_building(building: SimBuilding) -> void:
	var view := BuildingView.new()
	var faction: SimFaction = GameState.world.get_faction(building.faction_id)
	_entities.add_child(view)
	view.bind(building, faction.era)


func _add_unit(unit: SimUnit) -> void:
	var view := UnitView.new()
	var faction: SimFaction = GameState.world.get_faction(unit.faction_id)
	_entities.add_child(view)
	view.bind(unit, faction.era)


func _add_node_marker(node: SimResourceNode) -> void:
	var inst := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	if node.is_rare():
		mesh.size = Vector3(0.03, 0.045, 0.03)
	else:
		mesh.size = Vector3(0.026, 0.03, 0.026)
	var material := StandardMaterial3D.new()
	material.albedo_color = node.data.pin_color
	if node.is_rare():
		material.emission_enabled = true
		material.emission = node.data.pin_color * 0.45
	mesh.material = material
	inst.mesh = mesh
	inst.position = node.position + Vector3(0.0, 0.02, 0.0)
	inst.set_meta("node_id", node.node_id)
	inst.visible = _player_can_see(node)
	_nodes_root.add_child(inst)


func _on_building_placed(_fid: StringName, building_id: int, _type: StringName, _cell: Vector2i) -> void:
	if GameState.world == null:
		return
	var building: SimBuilding = GameState.world.playable.get_building(building_id)
	if building != null:
		_add_building(building)


func _on_unit_spawned(_fid: StringName, unit_id: int, _type: StringName, _pos: Vector3) -> void:
	if GameState.world == null:
		return
	var unit: SimUnit = GameState.world.playable.get_unit(unit_id)
	if unit != null:
		_add_unit(unit)


func _on_tier(new_tier: int, _prev: int) -> void:
	var region_or_closer: bool = new_tier >= int(GameState.ZoomTier.REGION)
	var rts: bool = new_tier >= int(GameState.ZoomTier.RTS)
	_entities.visible = rts
	_nodes_root.visible = region_or_closer
	# Square cell grid stays hidden; the faint hex overlay is shown only in
	# Tier 3 build/claim mode (HexOverlay listens for those signals itself).
	grid.visible = false


func _player_can_see(node: SimResourceNode) -> bool:
	if GameState.world == null:
		return not node.is_rare()
	return GameState.world.can_see_node(GameState.get_player_faction_id(), node)


func _on_era_changed(faction_id: StringName, _new_era: EraData, _prev: EraData) -> void:
	if faction_id != GameState.get_player_faction_id() or GameState.world == null:
		return
	for child in _nodes_root.get_children():
		var node_id: StringName = child.get_meta("node_id", &"") as StringName
		var node: SimResourceNode = GameState.world.playable.get_node(node_id)
		if node != null:
			child.visible = _player_can_see(node)
