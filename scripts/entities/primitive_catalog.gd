class_name PrimitiveCatalog
extends Object
## Fills EraData mesh slots with primitive meshes so era swaps are visible
## without art files. Later eras grow slightly taller and shift color.

const BUILDING_SIZES: Dictionary = {
	&"town_center": Vector3(0.08, 0.07, 0.08),
	&"house": Vector3(0.05, 0.045, 0.05),
	&"farm": Vector3(0.06, 0.03, 0.06),
	&"lumber_camp": Vector3(0.055, 0.04, 0.055),
	&"quarry": Vector3(0.055, 0.035, 0.055),
	&"barracks": Vector3(0.07, 0.05, 0.07),
	&"foundry": Vector3(0.07, 0.055, 0.06),
	&"extractor": Vector3(0.04, 0.06, 0.04),
	&"outpost": Vector3(0.04, 0.08, 0.04),
}

const ERA_TINTS: Array[Color] = [
	Color(0.55, 0.48, 0.38), # Stone / Clockwork
	Color(0.72, 0.52, 0.28), # Bronze / Steamworks
	Color(0.45, 0.48, 0.52), # Iron / Assembly
	Color(0.6, 0.64, 0.7), # Industrial / Synthetics
]


static func apply_to_eras(eras: Array[EraData]) -> void:
	for era: EraData in eras:
		apply_to_era(era)


static func apply_to_era(era: EraData) -> void:
	if era == null:
		return
	var tint: Color = ERA_TINTS[clampi(era.era_index, 0, ERA_TINTS.size() - 1)]
	var height_bonus: float = 1.0 + 0.12 * float(era.era_index)
	for building_id: StringName in BUILDING_SIZES:
		var size: Vector3 = BUILDING_SIZES[building_id] as Vector3
		size.y *= height_bonus
		era.building_meshes[building_id] = _box(size, tint)
	era.unit_meshes[SimIds.WORKER] = _sphere(0.014 * height_bonus, tint.lightened(0.15))
	era.unit_meshes[SimIds.SOLDIER] = _sphere(0.016 * height_bonus, tint.darkened(0.1))
	era.unit_meshes[SimIds.IRONCLAD] = _sphere(0.018 * height_bonus, Color(0.55, 0.58, 0.62))
	era.unit_meshes[SimIds.STEAMWALKER] = _sphere(0.02 * height_bonus, Color(0.35, 0.3, 0.22))


static func _box(size: Vector3, color: Color) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _mat(color)
	return mesh


static func _sphere(radius: float, color: Color) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.material = _mat(color)
	return mesh


static func _mat(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.7
	return material
