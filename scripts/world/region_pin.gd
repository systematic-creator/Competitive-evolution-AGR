class_name RegionPin
extends Node3D
## Clickable globe pin with optional rare-resource icons (iron / coal).

var region_id: StringName = &""
var is_accessible: bool = false
var _hovered: bool = false
var stem: MeshInstance3D
var head: MeshInstance3D
var _data: RegionData
var _icon_root: Node3D


func setup(data: RegionData, radius: float, color: Color) -> void:
	_data = data
	region_id = data.region_id
	is_accessible = data.is_accessible
	if not EventBus.era_changed.is_connected(_on_era_changed):
		EventBus.era_changed.connect(_on_era_changed)
	var lat: float = deg_to_rad(data.latitude_deg)
	var lon: float = deg_to_rad(data.longitude_deg)
	position = Vector3(
		cos(lat) * sin(lon),
		sin(lat),
		cos(lat) * cos(lon)
	) * radius
	look_at(Vector3.ZERO, Vector3.UP)
	rotate_object_local(Vector3.RIGHT, -PI / 2.0)
	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.004
	stem_mesh.bottom_radius = 0.004
	stem_mesh.height = 0.04
	stem = _mesh(stem_mesh, Vector3(0.0, 0.02, 0.0), color.darkened(0.2))
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.012 if is_accessible else 0.009
	head_mesh.height = head_mesh.radius * 2.0
	head = _mesh(head_mesh, Vector3(0.0, 0.045, 0.0), color if is_accessible else color.darkened(0.35))
	_add_rare_icons(data)
	var area := Area3D.new()
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.03
	col.shape = shape
	area.add_child(col)
	area.input_ray_pickable = true
	area.input_event.connect(_on_input_event)
	add_child(area)


func _add_rare_icons(data: RegionData) -> void:
	if _icon_root != null:
		_icon_root.queue_free()
	_icon_root = Node3D.new()
	_icon_root.name = "RareIcons"
	add_child(_icon_root)
	var visible_ids: Array[StringName] = []
	for resource_id: StringName in data.rare_resources:
		if GameState.world != null and not GameState.world.can_see_resource(GameState.get_player_faction_id(), resource_id):
			continue
		visible_ids.append(resource_id)
	var index: int = 0
	for resource_id: StringName in visible_ids:
		var icon := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.01, 0.01, 0.01)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.62, 0.66, 0.72) if resource_id == SimIds.IRON else Color(0.12, 0.1, 0.1)
		material.emission_enabled = true
		material.emission = material.albedo_color * 0.35
		mesh.material = material
		icon.mesh = mesh
		var side: float = -0.018 if index == 0 else 0.018
		if visible_ids.size() == 1:
			side = 0.0
		icon.position = Vector3(side, 0.06, 0.0)
		_icon_root.add_child(icon)
		index += 1


func _mesh(mesh: PrimitiveMesh, pos: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = is_accessible
	material.emission = color * 0.4
	mesh.material = material
	instance.mesh = mesh
	instance.position = pos
	add_child(instance)
	return instance


func _on_input_event(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape: int) -> void:
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			EventBus.region_selected.emit(region_id)


func _on_era_changed(faction_id: StringName, _new_era: EraData, _prev: EraData) -> void:
	if _data == null or faction_id != GameState.get_player_faction_id():
		return
	_add_rare_icons(_data)
