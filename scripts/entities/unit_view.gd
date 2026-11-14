class_name UnitView
extends CharacterBody3D
## Visual unit. A pure follower of the simulation, in DIORAMA-LOCAL space:
## `position` (relative to the diorama's Entities node) tracks `SimUnit.position`
## and never writes back to the sim. The diorama can therefore sit under any
## AR anchor pose / scale without changing what the sim sees.

const HOVER: Vector3 = Vector3(0.0, 0.02, 0.0)
const FOLLOW_SHARPNESS: float = 8.0
const COMBAT_FOLLOW_SHARPNESS: float = 12.0

var unit_id: int = 0
var _slot: Node3D
var _selected: bool = false
var _last_local: Vector3 = Vector3.ZERO


func _ready() -> void:
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
	EventBus.skirmish_unit_damaged.connect(_on_skirmish_damaged)
	set_physics_process(true)


func bind(unit: SimUnit, era: EraData) -> void:
	unit_id = unit.id
	position = local_target(unit)
	_last_local = position
	_refresh_mesh(unit, era)


## Diorama-local position this view should sit at for `unit`.
static func local_target(unit: SimUnit) -> Vector3:
	return unit.position + HOVER


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
	var sharpness: float = COMBAT_FOLLOW_SHARPNESS if unit.in_combat else FOLLOW_SHARPNESS
	var weight: float = clampf(delta * sharpness, 0.0, 1.0)
	position = position.lerp(local_target(unit), weight)
	if unit.in_combat:
		rotation.y = lerp_angle(rotation.y, unit.facing, weight)
	else:
		var moved: Vector3 = position - _last_local
		moved.y = 0.0
		if moved.length() > 0.0005:
			rotation.y = lerp_angle(rotation.y, SkirmishCombat.yaw_for_direction(moved), weight)
	_last_local = position


func _on_skirmish_damaged(_skirmish_id: int, id: int, _hp: int, _max_hp: int) -> void:
	if id != unit_id or not is_inside_tree():
		return
	_slot.scale = Vector3.ONE * 1.35
	var tween: Tween = create_tween()
	tween.tween_property(_slot, "scale", Vector3.ONE, 0.18)


func _on_era_changed(faction_id: StringName, new_era: EraData, _prev: EraData) -> void:
	if GameState.world == null:
		return
	var unit: SimUnit = GameState.world.playable.get_unit(unit_id)
	if unit != null and unit.faction_id == faction_id:
		_refresh_mesh(unit, new_era)
