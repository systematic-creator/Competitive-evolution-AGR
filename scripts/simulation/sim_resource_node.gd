class_name SimResourceNode
extends RefCounted
## A gatherable node instance on the region grid, backed by ResourceNodeData.

var node_id: StringName = &""
var data: ResourceNodeData
var cell: Vector2i = Vector2i.ZERO
var position: Vector3 = Vector3.ZERO
var remaining: int = 0
var capacity: int = 0
## Axial hex of this node's world position.
var hex: Vector2i = Vector2i.ZERO
## Soft claim: a structure's territory covers the node's center hex.
var soft_claimer: StringName = &""
## Hard claim: a constructed outpost sits on or next to the node.
var hard_claimer: StringName = &""
var claimed_outpost_id: int = -1


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


func controller() -> StringName:
	if hard_claimer != &"":
		return hard_claimer
	return soft_claimer
