class_name RegionData
extends Resource
## A globe region: pin location, accessibility, diorama grid, and rare resources.
## Instances live as `.tres` files in `res://data/regions/`.

@export var region_id: StringName = &""
@export var display_name: String = ""
@export var is_accessible: bool = false
## Empty when the region is contested or unowned. Used for globe territory color.
@export var owner_faction_id: StringName = &""
@export_range(-90.0, 90.0, 0.1) var latitude_deg: float = 0.0
@export_range(-180.0, 180.0, 0.1) var longitude_deg: float = 0.0
@export var grid_size: Vector2i = Vector2i(16, 16)
@export var cell_size: float = 0.0625
## Rare resources present in this region (shown as icons on the Tier 1 pin).
@export var rare_resources: Array[StringName] = []
