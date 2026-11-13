class_name OrbitGlobe
extends Node3D
## Territory-colored globe with region pins and rare-resource icons.

const RADIUS: float = 0.35

var _spin: float = 0.15
var _sphere: MeshInstance3D


func _ready() -> void:
	_sphere = MeshInstance3D.new()
	add_child(_sphere)
	if GameState.world != null:
		rebuild(GameState.world)
	EventBus.world_bootstrapped.connect(_on_boot)
	set_process(true)


func _on_boot() -> void:
	if GameState.world != null:
		rebuild(GameState.world)


func rebuild(world: SimWorld) -> void:
	for child in get_children():
		if child != _sphere:
			child.queue_free()
	_sphere.mesh = _build_territory_mesh(world)
	var globe_mat := StandardMaterial3D.new()
	globe_mat.vertex_color_use_as_albedo = true
	globe_mat.roughness = 0.85
	_sphere.material_override = globe_mat
	for data: RegionData in world.region_catalog:
		var pin := RegionPin.new()
		var color: Color = Color(0.75, 0.75, 0.7)
		if data.owner_faction_id != &"":
			var faction: SimFaction = world.get_faction(data.owner_faction_id)
			if faction != null and faction.data != null:
				color = faction.data.faction_color
		if data.is_accessible:
			color = Color(0.95, 0.85, 0.4)
		add_child(pin)
		pin.setup(data, RADIUS + 0.01, color)


func _process(delta: float) -> void:
	rotate_y(_spin * delta)


func _build_territory_mesh(world: SimWorld) -> ArrayMesh:
	var rings: int = 28
	var segments: int = 36
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pins: Array[RegionData] = world.region_catalog
	for i: int in range(rings):
		var v0: float = float(i) / float(rings)
		var v1: float = float(i + 1) / float(rings)
		var lat0: float = lerp(-PI / 2.0, PI / 2.0, v0)
		var lat1: float = lerp(-PI / 2.0, PI / 2.0, v1)
		for j: int in range(segments):
			var u0: float = float(j) / float(segments)
			var u1: float = float(j + 1) / float(segments)
			var lon0: float = lerp(-PI, PI, u0)
			var lon1: float = lerp(-PI, PI, u1)
			var p00 := _sph(lat0, lon0)
			var p10 := _sph(lat0, lon1)
			var p01 := _sph(lat1, lon0)
			var p11 := _sph(lat1, lon1)
			var mid := (p00 + p11) * 0.5
			var color: Color = _color_for_point(mid, pins, world)
			_tri(st, p00, p10, p11, color)
			_tri(st, p00, p11, p01, color)
	st.generate_normals()
	return st.commit()


func _sph(lat: float, lon: float) -> Vector3:
	return Vector3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon)) * RADIUS


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	st.set_color(color)
	st.set_normal(a.normalized())
	st.add_vertex(a)
	st.set_color(color)
	st.set_normal(b.normalized())
	st.add_vertex(b)
	st.set_color(color)
	st.set_normal(c.normalized())
	st.add_vertex(c)


func _color_for_point(point: Vector3, pins: Array[RegionData], world: SimWorld) -> Color:
	var best: RegionData = null
	var best_dist: float = INF
	var dir: Vector3 = point.normalized()
	for data: RegionData in pins:
		var lat: float = deg_to_rad(data.latitude_deg)
		var lon: float = deg_to_rad(data.longitude_deg)
		var pin_dir := Vector3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon))
		var dist: float = dir.distance_to(pin_dir)
		if dist < best_dist:
			best_dist = dist
			best = data
	var ocean := Color(0.15, 0.28, 0.42)
	if best == null or best.owner_faction_id == &"":
		return ocean.lerp(Color(0.22, 0.45, 0.28), 0.45 if (best != null and best.is_accessible) else 0.15)
	var faction: SimFaction = world.get_faction(best.owner_faction_id)
	if faction == null or faction.data == null:
		return ocean
	return faction.data.faction_color.darkened(0.25).lerp(ocean, 0.2)
