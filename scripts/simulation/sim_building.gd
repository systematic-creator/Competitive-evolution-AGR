class_name SimBuilding
extends RefCounted
## One building instance in the authoritative simulation.

var id: int = 0
var faction_id: StringName = &""
var building_type: StringName = &""
var grid_pos: Vector2i = Vector2i.ZERO
var hp: int = 100
var max_hp: int = 100
var constructed: bool = false
var build_progress: float = 0.0
var build_ticks_required: int = 1


func is_complete() -> bool:
	return constructed
