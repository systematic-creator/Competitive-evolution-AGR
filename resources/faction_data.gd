class_name FactionData
extends Resource
## Playable or AI faction: identity, species, color, and home region.
## Instances live as `.tres` files in `res://data/factions/`.

@export var faction_id: StringName = &""
@export var display_name: String = ""
@export var is_player: bool = false
@export var species: SpeciesData
@export var faction_color: Color = Color.WHITE
@export var home_region_id: StringName = &""
