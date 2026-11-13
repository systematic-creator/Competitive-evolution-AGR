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


func set_destination(dest: Vector3) -> void:
	destination = dest
	has_destination = true


func clear_destination() -> void:
	has_destination = false
	assigned_node_id = &""
