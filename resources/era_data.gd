class_name EraData
extends Resource
## Data definition for one technological era (Stone, Bronze, Industrial, ...).
##
## Instances live as `.tres` files in `res://data/eras/`. When
## `EventBus.era_changed` fires, Building/Unit nodes look up their visual here
## by ID and swap their child mesh/scene without touching gameplay state.

@export var era_name: String = ""

## Ordering index; higher means more advanced. Must be unique across eras.
@export var era_index: int = 0

## Building ID (StringName, e.g. `&"town_center"`) -> PackedScene or Mesh.
@export var building_meshes: Dictionary = {}

## Unit ID (StringName, e.g. `&"worker"`) -> PackedScene or Mesh.
@export var unit_meshes: Dictionary = {}

## Global resource production multiplier applied during this era.
@export_range(0.0, 10.0, 0.01, "or_greater") var production_multiplier: float = 1.0


func has_building(building_id: StringName) -> bool:
	return building_meshes.has(building_id)


func has_unit(unit_id: StringName) -> bool:
	return unit_meshes.has(unit_id)


## Returns the raw PackedScene or Mesh for a building, or null if undefined.
func get_building_visual(building_id: StringName) -> Resource:
	return building_meshes.get(building_id) as Resource


## Returns the raw PackedScene or Mesh for a unit, or null if undefined.
func get_unit_visual(unit_id: StringName) -> Resource:
	return unit_meshes.get(unit_id) as Resource


## Builds a ready-to-add Node3D for a building's visual, or null if undefined.
func instantiate_building_visual(building_id: StringName) -> Node3D:
	return _instantiate_visual(get_building_visual(building_id))


## Builds a ready-to-add Node3D for a unit's visual, or null if undefined.
func instantiate_unit_visual(unit_id: StringName) -> Node3D:
	return _instantiate_visual(get_unit_visual(unit_id))


static func _instantiate_visual(visual: Resource) -> Node3D:
	if visual is PackedScene:
		var node: Node = (visual as PackedScene).instantiate()
		if node is Node3D:
			return node as Node3D
		push_error("EraData: PackedScene root must be a Node3D, got %s" % node.get_class())
		node.free()
		return null
	if visual is Mesh:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = visual as Mesh
		return mesh_instance
	if visual != null:
		push_error("EraData: visual must be a PackedScene or Mesh, got %s" % visual.get_class())
	return null
