class_name HexOverlay
extends Node3D
## Faint hex overlay shown only in Tier 3 (RTS) build/claim mode.
## Borders are drawn from hex ownership; the square build grid stays hidden.

var _lines: MeshInstance3D
var _fills: MeshInstance3D
var _visible_wanted: bool = false


func _ready() -> void:
	_fills = MeshInstance3D.new()
	_fills.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_fills)
	_lines = MeshInstance3D.new()
	_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lines)
	EventBus.zoom_tier_changed.connect(_on_mode)
	EventBus.build_mode_changed.connect(_on_build_mode)
	EventBus.simulation_ticked.connect(_on_tick)
	EventBus.hex_claimed.connect(_on_claim_event)
	EventBus.hex_claim_released.connect(_on_release_event)
	visible = false


func _on_mode(_new_tier: int, _prev: int) -> void:
	_refresh_visibility()


func _on_build_mode(_active: bool) -> void:
	_refresh_visibility()


func _on_tick(_tick: int) -> void:
	if visible:
		rebuild()


func _on_claim_event(_fid: StringName, _hex: Vector2i, _bid: int) -> void:
	if visible:
		rebuild()


func _on_release_event(_fid: StringName, _hex: Vector2i, _bid: int) -> void:
	if visible:
		rebuild()


func _refresh_visibility() -> void:
	var rts: bool = GameState.current_zoom_tier == GameState.ZoomTier.RTS
	visible = rts and GameState.build_or_claim_mode
	if visible:
		rebuild()


func rebuild() -> void:
	if GameState.world == null or GameState.world.playable == null:
		return
	var region: SimRegion = GameState.world.playable
	var grid: HexGrid = region.hex_grid
	if grid == null:
		return
	var size: Vector2i = region.grid_size()
	var seen: Dictionary = {}
	var hexes: Array[Vector2i] = []
	for x: int in size.x:
		for y: int in size.y:
			var hex: Vector2i = region.hex_at_cell(Vector2i(x, y))
			var key: int = HexGrid.pack(hex)
			if seen.has(key):
				continue
			seen[key] = true
			hexes.append(hex)
	_build_fills(region, grid, hexes)
	_build_lines(region, grid, hexes)


func _build_lines(region: SimRegion, grid: HexGrid, hexes: Array[Vector2i]) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	for hex: Vector2i in hexes:
		var corners: PackedVector3Array = grid.corners(hex)
		var owner: StringName = region.hex_owner(hex)
		for i: int in 6:
			var a: Vector3 = corners[i]
			var b: Vector3 = corners[(i + 1) % 6]
			a.y = 0.003
			b.y = 0.003
			st.add_vertex(a)
			st.add_vertex(b)
			var neighbor: Vector2i = hex + HexGrid.DIRS[i]
			var nowner: StringName = region.hex_owner(neighbor)
			if owner != nowner and (owner != &"" or nowner != &""):
				# Border edge: slightly raised, drawn twice for weight.
				var a2: Vector3 = a + Vector3(0.0, 0.001, 0.0)
				var b2: Vector3 = b + Vector3(0.0, 0.001, 0.0)
				st.add_vertex(a2)
				st.add_vertex(b2)
	var mesh: ArrayMesh = st.commit()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 1.0, 1.0, 0.22)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = false
	_lines.mesh = mesh
	_lines.material_override = material


func _build_fills(region: SimRegion, grid: HexGrid, hexes: Array[Vector2i]) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for hex: Vector2i in hexes:
		var owner: StringName = region.hex_owner(hex)
		if owner == &"":
			continue
		var faction: SimFaction = GameState.world.get_faction(owner)
		var color: Color = Color(0.8, 0.8, 0.8, 0.1)
		if faction != null and faction.data != null:
			color = faction.data.faction_color
			color.a = 0.16
		var corners: PackedVector3Array = grid.corners(hex)
		var center: Vector3 = grid.axial_to_world(hex)
		center.y = 0.002
		for i: int in 6:
			var a: Vector3 = corners[i]
			var b: Vector3 = corners[(i + 1) % 6]
			a.y = 0.002
			b.y = 0.002
			st.set_color(color)
			st.add_vertex(center)
			st.add_vertex(a)
			st.add_vertex(b)
	var mesh: ArrayMesh = st.commit()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1, 1, 1, 1)
	material.vertex_color_use_as_albedo = true
	_fills.mesh = mesh
	_fills.material_override = material
