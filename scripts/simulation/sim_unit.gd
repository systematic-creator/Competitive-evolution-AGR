class_name SimUnit
extends RefCounted
## One unit instance in the authoritative simulation.

var id: int = 0
var faction_id: StringName = &""
var unit_type: StringName = &""
var position: Vector3 = Vector3.ZERO
var destination: Vector3 = Vector3.ZERO
var has_destination: bool = false
var assigned_node_id: StringName = &""
var hp: int = 40
var max_hp: int = 40
var speed: float = 0.14
## When a UnitView is attached it drives motion via NavigationAgent3D.
var view_attached: bool = false
## True while the unit fights in a live Tier 4 skirmish. SkirmishCombat owns its
## position then; normal movement and view-driven navigation stand down.
var in_combat: bool = false
## Yaw (radians, Godot rotation.y convention) the unit last faced in combat.
var facing: float = 0.0


func set_destination(dest: Vector3) -> void:
	destination = dest
	has_destination = true


func clear_destination() -> void:
	has_destination = false
	assigned_node_id = &""
