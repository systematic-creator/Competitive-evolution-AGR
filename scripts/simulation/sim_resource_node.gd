class_name SimResourceNode
extends RefCounted
## A gatherable node instance on the region grid, backed by ResourceNodeData.

var node_id: StringName = &""
var data: ResourceNodeData
var cell: Vector2i = Vector2i.ZERO
var position: Vector3 = Vector3.ZERO
var remaining: int = 0
var capacity: int = 0


func resource_id() -> StringName:
	return &"" if data == null else data.resource_id


func is_rare() -> bool:
	return data != null and data.is_rare


func base_gather() -> int:
	return 0 if data == null else data.base_gather


func display_name() -> String:
	return "" if data == null else data.display_name


func reveal_era() -> int:
	return 0 if data == null else data.reveal_era
