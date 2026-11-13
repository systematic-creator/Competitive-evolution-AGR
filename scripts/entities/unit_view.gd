class_name UnitView
extends CharacterBody3D
## Visual unit driven by NavigationAgent3D toward the sim destination.

var unit_id: int = 0
var agent: NavigationAgent3D
var _slot: Node3D
var _selected: bool = false


func _ready() -> void:
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 0.02
	agent.target_desired_distance = 0.02
	agent.avoidance_enabled = false
	add_child(agent)
	_slot = Node3D.new()
	add_child(_slot)
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.015
	shape.height = 0.04
	col.shape = shape
	col.position = Vector3(0.0, 0.02, 0.0)
	add_child(col)
	EventBus.era_changed.connect(_on_era_changed)
	EventBus.unit_destination_set.connect(_on_destination)
	set_physics_process(true)


func bind(unit: SimUnit, era: EraData) -> void:
	unit_id = unit.id
	global_position = unit.position + Vector3(0.0, 0.02, 0.0)
	unit.view_attached = true
	_refresh_mesh(unit, era)
	if unit.has_destination:
		agent.target_position = unit.destination


func set_selected(flag: bool) -> void:
	_selected = flag


func _refresh_mesh(unit: SimUnit, era: EraData) -> void:
	for child in _slot.get_children():
		child.queue_free()
	if era == null:
		return
	var visual: Node3D = era.instantiate_unit_visual(unit.unit_type)
	if visual != null:
		_slot.add_child(visual)


func _physics_process(delta: float) -> void:
	if GameState.world == null:
		return
	var unit: SimUnit = GameState.world.playable.get_unit(unit_id)
	if unit == null:
		queue_free()
		return
	if unit.has_destination:
		agent.target_position = unit.destination
		if not agent.is_navigation_finished():
			var next: Vector3 = agent.get_next_path_position()
			var offset: Vector3 = next - global_position
			offset.y = 0.0
			if offset.length() > 0.0001:
				velocity = offset.normalized() * unit.speed
				look_at(global_position + offset, Vector3.UP)
				move_and_slide()
			unit.position = Vector3(global_position.x, 0.0, global_position.z)
		else:
			unit.position = unit.destination
			global_position = unit.destination + Vector3(0.0, 0.02, 0.0)
	else:
		global_position = global_position.lerp(unit.position + Vector3(0.0, 0.02, 0.0), clampf(delta * 8.0, 0.0, 1.0))


func _on_destination(id: int, destination: Vector3) -> void:
	if id == unit_id:
		agent.target_position = destination


func _on_era_changed(faction_id: StringName, new_era: EraData, _prev: EraData) -> void:
	if GameState.world == null:
		return
	var unit: SimUnit = GameState.world.playable.get_unit(unit_id)
	if unit != null and unit.faction_id == faction_id:
		_refresh_mesh(unit, new_era)
