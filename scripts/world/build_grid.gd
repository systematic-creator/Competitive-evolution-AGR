class_name BuildGrid
extends MeshInstance3D
## RTS-only overlay of the playable region's cell grid.


func rebuild(region: SimRegion) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1, 1, 1, 0.28)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var size: Vector2i = region.grid_size()
	for x: int in range(size.x + 1):
		var a: Vector3 = region.cell_to_world(Vector2i(mini(x, size.x - 1), 0))
		var b: Vector3 = region.cell_to_world(Vector2i(mini(x, size.x - 1), size.y - 1))
		if x == size.x:
			a.x += region.cell_size() * 0.5
			b.x += region.cell_size() * 0.5
		else:
			a.x -= region.cell_size() * 0.5
			b.x -= region.cell_size() * 0.5
		a.y = 0.002
		b.y = 0.002
		st.add_vertex(a)
		st.add_vertex(b)
	for y: int in range(size.y + 1):
		var a: Vector3 = region.cell_to_world(Vector2i(0, mini(y, size.y - 1)))
		var b: Vector3 = region.cell_to_world(Vector2i(size.x - 1, mini(y, size.y - 1)))
		if y == size.y:
			a.z += region.cell_size() * 0.5
			b.z += region.cell_size() * 0.5
		else:
			a.z -= region.cell_size() * 0.5
			b.z -= region.cell_size() * 0.5
		a.y = 0.002
		b.y = 0.002
		st.add_vertex(a)
		st.add_vertex(b)
	mesh = st.commit()
	material_override = material
