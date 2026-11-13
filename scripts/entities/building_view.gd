class_name BuildingView
extends Node3D
## Visual for a SimBuilding; swaps era meshes on EventBus.era_changed.

var building_id: int = 0
var _slot: Node3D


func _ready() -> void:
	_slot = Node3D.new()
	_slot.position = Vector3(0.0, 0.0, 0.0)
	add_child(_slot)
	EventBus.era_changed.connect(_on_era_changed)
	EventBus.building_constructed.connect(_on_constructed)


func bind(building: SimBuilding, era: EraData) -> void:
	if _slot == null:
		_slot = Node3D.new()
		add_child(_slot)
	building_id = building.id
	position = _world_of(building)
	refresh_mesh(building, era)
	scale = Vector3.ONE * (0.7 if not building.constructed else 1.0)


func refresh_mesh(building: SimBuilding, era: EraData) -> void:
	if _slot == null:
		return
	for child in _slot.get_children():
		child.queue_free()
	if era == null:
		return
	var visual: Node3D = era.instantiate_building_visual(building.building_type)
	if visual != null:
		_slot.add_child(visual)


func _world_of(building: SimBuilding) -> Vector3:
	if GameState.world == null:
		return Vector3.ZERO
	var pos: Vector3 = GameState.world.playable.cell_to_world(building.grid_pos)
	pos.y = 0.0
	return pos


func _on_era_changed(faction_id: StringName, new_era: EraData, _prev: EraData) -> void:
	if GameState.world == null:
		return
	var building: SimBuilding = GameState.world.playable.get_building(building_id)
	if building == null or building.faction_id != faction_id:
		return
	refresh_mesh(building, new_era)


func _on_constructed(_faction_id: StringName, id: int, _type: StringName, _cell: Vector2i) -> void:
	if id != building_id or GameState.world == null:
		return
	var building: SimBuilding = GameState.world.playable.get_building(building_id)
	var faction: SimFaction = GameState.world.get_faction(building.faction_id)
	scale = Vector3.ONE
	refresh_mesh(building, faction.era)
